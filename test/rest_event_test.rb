require File.dirname(__FILE__) + "/helper"

context "An Event (in general)" do
  
  specify "should return 200 if match" do
    event = Sinatra::RESTEvent.new(:get, '/') {}
    status, _, _ = event.call(context_for('/'))
    assert_equal(200, status)
  end
  
  specify "should return default headers for match" do
    event = Sinatra::RESTEvent.new(:get, '/') {}
    _, headers, _ = event.call(context_for('/'))
    assert_equal({ 'Content-Type' => 'text/html' }, headers)
  end
  
  specify "should return response with body" do
    event = Sinatra::RESTEvent.new(:get, '/') { 'foo' }
    _, _, response = event.call(context_for('/'))
    assert_equal('foo', response.body)
  end
  
  specify "should return 200 status with empty body for nil return value" do
    event = Sinatra::RESTEvent.new(:get, '/') { nil }
    status, _, response = event.call(context_for('/'))
    assert_equal(200, status)
    assert_equal('', response.body)
  end
    
end

context "An Event halted" do
  
  specify "should call to_result on the halted value" do
    String.any_instance.expects(:to_result).with(kind_of(Sinatra::EventContext))
    event = Sinatra::RESTEvent.new(:get, '/') { throw :halt, 'test' }
    event.call(context_for('/'))
  end  
  
end
