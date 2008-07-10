require File.dirname(__FILE__) + "/helper"

class MyMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    env['test_var'] = 'X'
    @app.call(env)
  end
  
end

context "The pipeline" do
  
  specify "should execute middleware leading app" do
    app = Sinatra::Application.new do
      use MyMiddleware
      get '/' do
        request.env['test_var']
      end
    end
    _, _, response = app.call(env_for("/"))
    assert_equal('X', response.body)
  end

  specify "should install ShowError by default" do
    app = Sinatra::Application.new {}
    middleware = app.instance_eval { @middleware }
    assert_equal(1, middleware.size)
    assert_equal(Sinatra::ShowError, middleware.first.first)
  end
  
end