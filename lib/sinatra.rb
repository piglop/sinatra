require "rubygems"
require "rack"

class Object
  def tap
    yield self
    self
  end
end

module Enumerable
  
  def eject(&block)
    find { |e| result = block[e] and break result }
  end
  
end

module Sinatra
    
  class Application
    
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
        tap { |c| c.body = instance_eval(&b) }
      end
      alias :body :run_block
      
      def method_missing(sym, *args, &b)
        @response.send(sym, *args, &b)
      end
      
    end
    
    class Event
      
      def initialize(app, method, path, &b)
        @app    = app
        @method = method.to_sym
        @path   = path
        @block  = b
        raise "Event needs a block on initialize" unless b
      end
      
      def call(env)
        context = EventContext.new(env)
        invoke(context)
        context.finish
      end
      
      def invoke(context)
        context.status(99)
        if @method == context.request.request_method.downcase.to_sym && @path == context.request.path_info
          context.status(200)
          context.body(&@block)
        end
        context.finish
      end
      
    end
    
    module DSL

      def event(method, path, &b)
        apps << Event.new(self, method, path, &b)
      end
      
      def get(path, &b)
        event(:get, path, &b)
      end
      
    end
    include DSL

    def initialize(&b)
      @apps = []
      instance_eval(&b)
    end
    
    attr_reader :apps

    def call(env)
      Rack::Cascade.new(apps, 99).call(env)
    end
    
  end
  
end
