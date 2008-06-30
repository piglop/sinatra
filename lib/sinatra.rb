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
        @status = code if code
        @status
      end
      
      def run_block(&b)
        tap { |c| c.body = instance_eval(&b) }
      end
      
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
        context.run_block(&@block)
        context.finish
      end
      
      def invoke(context)
        unless @method == context.request.request_method.downcase.to_sym
          context.status(99)
        end
        unless @path == context.request.path_info
          context.status(99)
        end
        context.finish
      end
      
    end
    
    attr_reader :apps
    
    def initialize(&b)
      @apps = []
      instance_eval(&b)
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
    
    def call(env)
      status, headers, body = apps.eject do |app|
        app.call(env)
      end
    end
      
  end
  
end
