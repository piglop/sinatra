require "rubygems"
require "rack"
require "uri"
require "ostruct"

class Object
  def tap
    yield self
    self
  end
end

module Sinatra
  extend self

  class NotFound < Exception; end
  class ServerError < Exception; end

  class EventContext
    
    attr_reader :request, :response
    
    def initialize(env)
      @request = Rack::Request.new(env)
      @response = Rack::Response.new
    end
    
    def status(code = nil)
      @response.status = code if code
      @response.status
    end
    
    def run_block(&b)
      tap { |c| c.body = instance_eval(&b) || '' }
    end
    
    def method_missing(sym, *args, &b)
      @response.send(sym, *args, &b)
    end
    
    def fall
      stop(99)
    end
    
    def stop(*args)
      throw :halt, args
    end
    
    def params
      @params ||= request.params
    end
    
  end

  class Event
    
    def initialize(&b)
      raise "Event needs a block on initialize" unless b
      @block = b
    end
    
    def call(context)
      result = catch(:halt) do
        invoke(context)
        :complete
      end
      context.run_block do 
        result.to_result(context)
      end unless result == :complete
      context.finish
    end
    
    protected
    
      def invoke(context)
        context.run_block(&@block)
      end
    
  end
  
  class RESTEvent < Event
    
    URI_CHAR = '[^/?:,&#\.]'.freeze unless defined?(URI_CHAR)
    PARAM = /(:(#{URI_CHAR}+)|\*)/.freeze unless defined?(PARAM)
    SPLAT = /(.*?)/
        
    def initialize(method, path, &b)
      super(&b)
      @method = method.to_sym
      @path   = URI.encode(path)
      build_route!
    end
    
    protected

      def build_route!
        @param_keys = []
        regex = @path.to_s.gsub(PARAM) do |match|
          @param_keys << $2
          "(#{URI_CHAR}+)"
        end
        @pattern = /^#{regex}$/
      end
    
      def invoke(context)
        return context.fall unless @method == context.request.request_method.downcase.to_sym
        return context.fall unless @pattern =~ context.request.path_info
        params = @param_keys.zip($~.captures.map(&:from_param)).to_hash
        context.params.merge!(params)
        context.status(200)
        super(context)
      end
    
  end
    
  class Application
    
    attr_reader :events, :errors, :options

    # Hash of default application configuration options. When a new
    # Application is created, the #options object takes its initial values
    # from here.
    #
    # Changes to the default_options Hash effect only Application objects
    # created after the changes are made. For this reason, modifications to
    # the default_options Hash typically occur at the very beginning of a
    # file, before any DSL related functions are invoked.
    def self.default_options
      return @default_options unless @default_options.nil?
      root = File.expand_path(File.dirname($0))
      @default_options = {
        :run => true,
        :port => 4567,
        :host => '0.0.0.0',
        :env => :development,
        :root => root,
        :views => root + '/views',
        :public => root + '/public',
        :sessions => false,
        :logging => true,
        :app_file => $0,
        :error_logging => true,
        :raise_errors => false
      }
      load_default_options_from_command_line!
      @default_options
    end
    
    # Search ARGV for command line arguments and update the
    # Sinatra::default_options Hash accordingly. This method is
    # invoked the first time the default_options Hash is accessed.
    # NOTE:  Ignores --name so unit/spec tests can run individually
    def self.load_default_options_from_command_line! #:nodoc:
      require 'optparse'
      OptionParser.new do |op|
        op.on('-p port') { |port| default_options[:port] = port }
        op.on('-e env') { |env| default_options[:env] = env.to_sym }
        op.on('-x') { default_options[:mutex] = true }
        op.on('-s server') { |server| default_options[:server] = server }
      end.parse!(ARGV.dup.select { |o| o !~ /--name/ })
    end
    
    def server
      options.server ||= defined?(Rack::Handler::Thin) ? "thin" : "mongrel"

      # Convert the server into the actual handler name
      handler = options.server.capitalize

      # If the convenience conversion didn't get us anything, 
      # fall back to what the user actually set.
      handler = options.server unless Rack::Handler.const_defined?(handler)

      @server ||= eval("Rack::Handler::#{handler}")
    end
    
    def run
      return unless options.run
      require 'thin'
      begin
        puts "== Sinatra has taken the stage on port #{options.port} for #{options.env} with backup by #{server.name}"
        server.run(self, {:Port => options.port, :Host => options.host}) do |server|
          trap(:INT) do
            server.stop
            puts "\n== Sinatra has ended his set (crowd applauds)"
          end
        end
      rescue Errno::EADDRINUSE => e
        puts "== Someone is already performing on port #{options.port}!"
      end
    end
    
    def initialize(&b)
      @events     = []
      @errors     = {}
      @middleware = []
      @options = OpenStruct.new(self.class.default_options)
      
      error NotFound do
        stop 404, '<h1>Not Found</h1>'
      end
      
      error ServerError do
        stop 500, '<h1>Internal Server Error</h1>'
      end
                  
      instance_eval(&b)
    end
        
    def call(env)
      pipeline.call(env)
    end
    
    protected
    
      def pipeline
        @pipeline ||=
          middleware.inject(method(:dispatch)) do |app,(klass,args,block)|
            klass.new(app, *args, &block)
          end
      end
      
      ##
      # Adapted from Rack::Cascade
      def dispatch(env)
        context = EventContext.new(env)
        begin
          status, _ = run_events(context)
          if status == 99
            context.status(404)
            errors[NotFound].call(context) 
          end
          context.finish
        rescue => e
          error = errors[e.class] || errors[ServerError]
          if options.error_logging
            puts "#{e.class.name}: #{e.message}\n  #{e.backtrace.join("\n  ")}"
          end
          error.call(context)
        end
      end
      
      def run_events(context)
        raise "There are no events registered" if events.empty?
        status = headers = body = nil
        events.each do |event|
          status, headers, body = event.call(context)
          break unless status.to_i == 99
        end
        [status, headers, body]
      end
      
      # Rack middleware derived from current state of application options.
      # These components are plumbed in at the very beginning of the
      # pipeline.
      def optional_middleware
        [
          ([ Rack::CommonLogger,    [], nil ] if options.logging),
          ([ Rack::Session::Cookie, [], nil ] if options.sessions)
        ].compact
      end

      # Rack middleware explicitly added to the application with #use. These
      # components are plumbed into the pipeline downstream from
      # #optional_middle.
      def explicit_middleware
        @middleware
      end

      # All Rack middleware used to construct the pipeline.
      def middleware
        optional_middleware + explicit_middleware
      end
                
    module DSL

      def error(e, &b)
        errors[e] = Event.new(&b)
      end

      def event(method, path, &b)
        events << RESTEvent.new(method, path, &b)
      end
      
      def head(path, &b)
        event(:head, path, &b)
      end

      def get(path, &b)
        event(:get, path, &b)
      end

      def post(path, &b)
        event(:post, path, &b)
      end
      
      def put(path, &b)
        event(:put, path, &b)
      end
      
      def delete(path, &b)
        event(:delete, path, &b)
      end
      
      # Add a piece of Rack middleware to the pipeline leading to the
      # application.
      def use(klass, *args, &block)
        fail "#{klass} must respond to 'new'" unless klass.respond_to?(:new)
        @pipeline = nil
        @middleware.push([ klass, args, block ]).last
      end

      # Yield to the block for configuration if the current environment
      # matches any included in the +envs+ list. Always yield to the block
      # when no environment is specified.
      #
      # NOTE: configuration blocks are not executed during reloads.
      def configures(*envs, &b)
        return if reloading?
        yield self if envs.empty? || envs.include?(options.env)
      end

      alias :configure :configures

      # When both +option+ and +value+ arguments are provided, set the option
      # specified. With a single Hash argument, set all options specified in
      # Hash. Options are available via the Application#options object.
      #
      # Setting individual options:
      #   set :port, 80
      #   set :env, :production
      #   set :views, '/path/to/views'
      #
      # Setting multiple options:
      #   set :port  => 80,
      #       :env   => :production,
      #       :views => '/path/to/views'
      #
      def set(option, value=self)
        if value == self && option.kind_of?(Hash)
          option.each { |key,val| set(key, val) }
        else
          options.send("#{option}=", value)
        end
      end

      alias :set_option :set
      alias :set_options :set

      # Enable the options specified by setting their values to true. For
      # example, to enable sessions and logging:
      #   enable :sessions, :logging
      def enable(*opts)
        opts.each { |key| set(key, true) }
      end

      # Disable the options specified by setting their values to false. For
      # example, to disable logging and automatic run:
      #   disable :logging, :run
      def disable(*opts)
        opts.each { |key| set(key, false) }
      end
      
      # Determine whether the application is in the process of being
      # reloaded.
      def reloading?
        @reloading == true
      end
      
    end
    include DSL
        
  end
  
  module DelegatingDSL
    
    FORWARDABLE_METHODS = [ :get, :post, :put, :delete, :head, :error ]
    
    FORWARDABLE_METHODS.each do |method|
      eval(<<-EOS, binding, '(__DSL__)', 1)
        def #{method}(*args, &b)
          Sinatra.application.#{method}(*args, &b)
        end
      EOS
    end
    
  end
  
  def application
    @application ||= Application.new do
      configure do
        enable :logging
      end
    end
  end
  
end

include Sinatra::DelegatingDSL

module Rack

  module Utils
    extend self
  end
  
end

class Array
  
  def to_hash
    self.inject({}) { |h, (k, v)|  h[k] = v; h }
  end
  
  def to_proc
    Proc.new { |*args| args.shift.__send__(self[0], *(args + self[1..-1])) }
  end
  
end

class String

  # Converts +self+ to an escaped URI parameter value
  #   'Foo Bar'.to_param # => 'Foo%20Bar'
  def to_param
    Rack::Utils.escape(self)
  end
  alias :http_escape :to_param
  
  # Converts +self+ from an escaped URI parameter value
  #   'Foo%20Bar'.from_param # => 'Foo Bar'
  def from_param
    Rack::Utils.unescape(self)
  end
  alias :http_unescape :from_param
  
end

class Symbol
  
  def to_proc 
    Proc.new { |*args| args.shift.__send__(self, *args) }
  end
  
end

### Core Extension results for throw :halt

class Proc
  def to_result(cx, *args)
    cx.instance_eval(&self)
    args.shift.to_result(cx, *args)
  end
end

class String
  def to_result(cx, *args)
    args.shift.to_result(cx, *args)
    self
  end
end

class Array
  def to_result(cx, *args)
    self.shift.to_result(cx, *self)
  end
end

class Symbol
  def to_result(cx, *args)
    cx.send(self, *args)
  end
end

class Fixnum
  def to_result(cx, *args)
    cx.status self
    args.shift.to_result(cx, *args)
  end
end

class NilClass
  def to_result(cx, *args)
    ''
  end
end

at_exit do
  exit if $!
  Sinatra.application.run
end