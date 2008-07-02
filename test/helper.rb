$:.unshift File.dirname(__FILE__) + "/../lib"
require "sinatra"

require "rubygems"
require "test/spec"

class Test::Unit::TestCase
  
  def env_for(*args)
    Rack::MockRequest.env_for(*args)
  end
  
end
