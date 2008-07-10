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
      throw :halt, *args
    end
    
  end
  
  class Event
    
    URI_CHAR = '[^/?:,&#\.]'.freeze unless defined?(URI_CHAR)
    PARAM = /(:(#{URI_CHAR}+)|\*)/.freeze unless defined?(PARAM)
    SPLAT = /(.*?)/
    
    attr_reader :params
    
    def initialize(method, path, &b)
      @method = method.to_sym
      @path   = URI.encode(path)
      @block  = b
      raise "Event needs a block on initialize" unless b
      build_route!
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

      def build_route!
        @param_keys = []
        @params = {}
        regex = @path.to_s.gsub(PARAM) do |match|
          @param_keys << $2
          "(#{URI_CHAR}+)"
        end
        @pattern = /^#{regex}$/
      end
    
      def invoke(context)
        return context.fall unless @method == context.request.request_method.downcase.to_sym
        return context.fall unless @pattern =~ context.request.path_info
        @params.merge!(@param_keys.zip($~.captures.map(&:from_param)).to_hash)
        context.status(200)
        context.run_block(&@block)
      end
    
  end
  
  class ShowError
    def initialize(app)
      @app = app
    end
    
    def call(env)
      begin
        @app.call(env)
      rescue => e
        puts "#{e.class.name}: #{e.message}\n  #{e.backtrace.join("\n  ")}"
      end
    end
  end
  
  class ContextualCascade < Rack::Cascade
    
    def initialize(apps, catch=99)
      super(apps, catch)
    end
    
    def call(env)
      super(EventContext.new(env))
    end
    
  end
  
  class Application
    
    attr_reader :events, :options

    def initialize(&b)
      @events     = []
      @middleware = []
      @options = OpenStruct.new
      
      use ShowError
      
      instance_eval(&b)
    end
    
    def call(env)
      status, headers, body = pipeline.call(env)
      if status == 99
        [404, { 'Content-Type' => 'text/html' }, ['<h1>Not Found</h1>']]
      else
        [status, headers, body]
      end
    end

    protected
    
      def pipeline
        @pipeline ||=
          middleware.inject(dispatcher) do |app,(klass,args,block)|
            klass.new(app, *args, &block)
          end
      end
      
      def dispatcher
        @dispatcher ||= ContextualCascade.new(events, 99)
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

      def event(method, path, &b)
        events << Event.new(method, path, &b)
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
    
    FORWARDABLE_METHODS = [ :get, :post, :put, :delete, :head ]
    
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

