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

  class Error < RuntimeError
    def self.code(code=nil)
      @code = code if code
      @code || 500
    end
  end
  class NotFound < Error;     code(404); end
  class ServerError < Error;  code(500); end

  ##
  #
  #
  #
  # Template rendering
  #
  #
  #
  ##

  module RenderingHelpers

    def render(renderer, template, options={})
      m = method("render_#{renderer}")
      result = m.call(resolve_template(renderer, template, options), options)
      if layout = determine_layout(renderer, template, options)
        result = m.call(resolve_template(renderer, layout, options), options) { result }
      end
      result
    end
    
    def determine_layout(renderer, template, options)
      return if options[:layout] == false
      layout_from_options = options[:layout] || :layout
      resolve_template(renderer, layout_from_options, options, false)
    end

    private
        
      def resolve_template(renderer, template, options, scream = true)
        case template
        when String
          template
        when Proc
          template.call
        when Symbol
          if proc = templates[template]
            resolve_template(renderer, proc, options, scream)
          else
            read_template_file(renderer, template, options, scream)
          end
        else
          nil
        end
      end
      
      def read_template_file(renderer, template, options, scream = true)
        path = File.join(
          options[:views_directory] || Sinatra.application.options.views,
          "#{template}.#{renderer}"
        )
        unless File.exists?(path)
          raise Errno::ENOENT.new(path) if scream
          nil
        else  
          File.read(path)
        end
      end
      
      def templates
        options[:templates] || {}
      end
    
  end



  module Haml
    
    def haml(content, options={})
      require 'haml'
      render(:haml, content, options)
    end
    
    private
    
      def render_haml(content, options = {}, &b)
        haml_options = (options[:options] || {}).merge(options[:haml] || {})
        ::Haml::Engine.new(content, haml_options).render(options[:scope] || self, options[:locals] || {}, &b)
      end
        
  end



  module Erb
    
    def erb(content, options={})
      require 'erb'
      render(:erb, content, options)
    end
    
    private 
    
      def render_erb(content, options = {})
        locals_opt = options.delete(:locals) || {}

        locals_code = ""
        locals_hash = {} 
        locals_opt.each do |key, value|
          locals_code << "#{key} = locals_hash[:#{key}]\n"
          locals_hash[:"#{key}"] = value
        end
 
        body = ::ERB.new(content).src
        eval("#{locals_code}#{body}", binding)
      end

  end




  class EventContext
    include RenderingHelpers
    include Haml
    include Erb
    
    attr_reader   :request, :response
    attr_accessor :options
    
    def initialize(env)
      @request  = Rack::Request.new(env)
      @response = Rack::Response.new
      @options  = {}
    end
    
    def status(code = nil)
      @response.status = code if code
      @response.status
    end
    
    def run_block(&b)
      tap { |c| c.body = instance_eval(&b) || '' }
    end
    
    def method_missing(sym, *args, &b)
      if env.respond_to?(sym)
        env.send(sym, *args, &b)
      else
        @response.send(sym, *args, &b)
      end
    end
    
    def fall
      stop(99)
    end
    
    def stop(*args)
      throw :halt, args
    end
    
    def fall_group
      throw :halt_group
    end
            
    def params
      env['sinatra.params']
    end
    
    def env
      request.env
    end
    
  end

  ##
  #
  #
  #
  # Middleware
  #
  #
  #
  ##

  class EventLogger
    def initialize(app)
      @app = app
    end
    
    def call(env)
      @app.call(env).tap do |status,(headers, body)|
        puts
        puts "~ Request:\t#{env['PATH_INFO'].inspect}"
        puts "~ Params:\t#{env['sinatra.params'].inspect}"
        if status >= 300 && status < 400
          puts "~ Redirecting to:\t #{headers['Location'].inspect}"
        end
      end
    end
  end

  class Filter
    
    def initialize(options = {}, &b)
      raise "Event needs a block on initialize" unless b
      @block    = b
      @options  = options
    end
    
    def call(context)
      context.status(200)
      context.options = @options
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
  
  class Application
    
    attr_reader :events, :errors, :options, :o

    URI_CHAR = '[^/?:,&#\.]'.freeze unless defined?(URI_CHAR)
    PARAM = /(:(#{URI_CHAR}+)|\*)/.freeze unless defined?(PARAM)
    SPLAT = /(.*?)/

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
    
    def initialize(options = {}, &b)
      @events     = []
      @errors     = {}
      @middleware = []
      @o          = self.class.default_options.merge(options)
      @options    = OpenStruct.new(@o)
      
      @o[:templates] ||= {}

      configure :development do
        use EventLogger
      end
      
      error NotFound do
        stop 404, '<h1>Not Found</h1>'
      end
      
      error ServerError do
        stop 500, '<h1>Internal Server Error</h1>'
      end
                  
      instance_eval(&b)
    end
        
    def call(context)
      context = EventContext.new(context) unless context.is_a?(EventContext)
      result = catch :halt_group do
        pipeline.call(context)
        :complete
      end
      context.status(99) unless result == :complete
      context.finish
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
      def dispatch(context)
        begin
          status, _ = run_events(context)
          context.finish
        rescue Sinatra::Error => e
          raise e if options.raise_errors
          context.status(e.class.code)
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
    
    module Middleware
      
      class NotFoundHandler
        attr_reader :errors
        
        def initialize(app, errors)
          @app    = app
          @errors = errors
        end
        
        def call(env)
          status, *_ = @app.call(env)
          if status == 99
            status = 404
            errors[Sinatra::NotFound].call(env)
          else
            [status, *_]
          end
        end
      end
      
    end
    
    module DSL

      def error(e, &b)
        errors[e] = Filter.new(&b)
      end
      
      def filter(options = {}, &b)
        events << Filter.new(self.o.merge(options), &b)
      end
      
      def group(options = {}, &b)
        events << Application.new(self.o.merge(options), &b)
      end

      def event(method, path, options = {}, &b)
        path                  = URI.encode(path)
        
        options               = options.dup
        options[:method]      = method
        options[:path]        = path

        param_keys = []
        regex = path.to_s.gsub(PARAM) do |match|
          param_keys << $2
          "(#{URI_CHAR}+)"
        end

        options[:pattern]     = /^#{regex}$/
        options[:param_keys]  = param_keys
        
        group options do
          
          filter do
            request_method = request.request_method.downcase.to_sym
            
            fall_group unless options[:method]  == request_method
            fall_group unless options[:pattern] =~ request.path_info
            
            matches = $~.captures.map(&:from_param)
            params = options[:param_keys].zip(matches).to_hash
            env['sinatra.params'] = request.params.merge(params)
            
            fall
          end
          
          filter(&b)
          
        end
      end
      
      def head(path, options = {}, &b)
        event(:head, path, options, &b)
      end

      def get(path, options = {}, &b)
        event(:get, path, options, &b)
      end

      def post(path, options = {}, &b)
        event(:post, path, options, &b)
      end
      
      def put(path, options = {}, &b)
        event(:put, path, options, &b)
      end
      
      def delete(path, options = {}, &b)
        event(:delete, path, options, &b)
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