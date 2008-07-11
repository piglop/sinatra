require File.dirname(__FILE__) + "/helper"

class MyError < RuntimeError; end

context "Unregisterd Errors" do
  
  specify "should rise out of the applcation" do
    app = Sinatra::Application.new do
      get '/' do
        raise MyError, 'whoa!'
      end
    end
    response = Rack::MockRequest.new(app).get('/')
    assert_equal(500, response.status)
    assert_equal('<h1>Internal Server Error</h1>', response.body)
  end
  
end

context "Registerd Errors" do
  
  specify "should not rise out of the application" do
    app = Sinatra::Application.new do
      error MyError do
        'fubar'
      end
      
      get '/' do
        raise MyError
      end
    end
    response = Rack::MockRequest.new(app).get('/')
    assert_equal('fubar', response.body)
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
