require File.dirname(__FILE__) + "/helper"

class MyError < Exception; end

context "Unregisterd Errors" do
  
  specify "should rise out of the applcation" do
    app = Sinatra::Application.new do
      get '/' do
        raise MyError, 'whoa!'
      end
    end
    assert_raise(MyError) { Rack::MockRequest.new(app).get('/') }
  end
  
end

context "Registerd Errors" do
  
  specify "should not rise out of the application" do
    app = Sinatra::Application.new do
      get '/' do
        raise Sinatra::NotFound
      end
    end
    assert_nothing_raised(MyError) { Rack::MockRequest.new(app).get('/') }
  end

  # specify "should have their corisponding events invoked" do
  #   app = Sinatra::Application.new do
  #     get '/' do
  #       raise Sinatra::NotFound
  #     end
  #   end
  #   assert_raise(MyError) { Rack::MockRequest.new(app).get('/') }
  # end

end
