require File.dirname(__FILE__) + "/helper"

context "A Sinatra::Application" do
  
  specify "should return the result of the first valid Event" do
  
    app = Rack::Builder.new do
      run(Sinatra::Application.new do
        get '/' do
          'hello world'
        end
      end)
    end
    
    request = Rack::MockRequest.new(app)
    response = request.get('/')
    
    assert_equal(200, response.status)
    assert_equal({ 'Content-Type' => 'text/html' }, response.headers)
    assert_equal('hello world', response.body)
    
  end
  
end
