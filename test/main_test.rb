require File.dirname(__FILE__) + "/helper"

context "The main application" do
  
  specify "should be defined with methods on main" do
    
    get '/' do
      'testing'      
    end
    
    status, _, response = Sinatra.application.call(env_for("/"))
    
    assert_equal(200, status)
    assert_equal('testing', response.body)
    
  end
  
end
