require File.dirname(__FILE__) + "/helper"

context "An Event (in general)" do
  
  specify "should return 200 if match" do
    event = Sinatra::Event.new(:get, '/') {}
    status, _, _ = event.call(env_for('/'))
    assert_equal(200, status)
  end
  
  specify "should return default headers for match" do
    event = Sinatra::Event.new(:get, '/') {}
    _, headers, _ = event.call(env_for('/'))
    assert_equal({ 'Content-Type' => 'text/html' }, headers)
  end
  
  specify "should return response with body" do
    event = Sinatra::Event.new(:get, '/') { 'foo' }
    _, _, response = event.call(env_for('/'))
    assert_equal('foo', response.body)
  end
  
end

context "An Event halted" do
  
  specify "should call to_result on the halted value" do
    String.any_instance.expects(:to_result).with(kind_of(Sinatra::EventContext))
    event = Sinatra::Event.new(:get, '/') { throw :halt, 'test' }
    event.call(env_for('/'))
  end  
  
end
