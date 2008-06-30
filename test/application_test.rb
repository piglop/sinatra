require File.dirname(__FILE__) + "/helper"

context "A Sinatra::Application with one Event" do
  
  setup do
    @app = Rack::Builder.new do
      run(Sinatra::Application.new do
        get '/' do
          'hello world'
        end
      end)
    end
    
    @request = Rack::MockRequest.new(@app)
    @response = @request.get('/')
  end
  
  specify "should return 200 status if there is a valid Event" do
    assert_equal(200, @response.status)
  end
  
  specify "should return default headers" do
    assert_equal({ 'Content-Type' => 'text/html' }, @response.headers)
  end
    
  specify "should return blocks return value as the body" do
    assert_equal('hello world', @response.body)
  end
  
end

context "A Sinatra::Application with two Events" do

  setup do
    @app = Rack::Builder.new do
      run(Sinatra::Application.new do
        get '/' do
          'hello world'
        end
        
        get '/foo' do
          'in foo'
        end
      end)
    end
    
    @request = Rack::MockRequest.new(@app)
    @response = @request.get('/foo')
  end
  
  specify "should return 200 status if there is a valid Event" do
    assert_equal(200, @response.status)
  end
  
  specify "should return default headers" do
    assert_equal({ 'Content-Type' => 'text/html' }, @response.headers)
  end
    
  specify "should return blocks return value as the body" do
    assert_equal('in foo', @response.body)
  end
    
end

