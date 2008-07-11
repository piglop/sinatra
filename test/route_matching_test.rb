require File.dirname(__FILE__) + "/helper"

context "Routes" do
  
  specify "should match explicit paths" do
    event = Sinatra::RESTEvent.new(:get, '/foo') {}
    status, _ = event.call(context_for('/foo'))
    assert_equal(200, status)
  end

  specify "should match explicit paths with spaces" do
    event = Sinatra::RESTEvent.new(:get, '/foo bar') {}
    status, _ = event.call(context_for('/foo%20bar'))
    assert_equal(200, status)
  end
  
end

context "Routes with params" do

  specify "should match variables in paths" do
    event = Sinatra::RESTEvent.new(:get, '/foo/:bar') {}
    status, _ = event.call(context_for('/foo/baz'))
    assert_equal(200, status)
  end
  
  specify "should expose values of route params" do
    event = Sinatra::RESTEvent.new(:get, '/foo/:bar') { params['bar'] }
    status, _, response = event.call(context_for('/foo/baz'))
    assert_equal('baz', response.body)
  end
    
end