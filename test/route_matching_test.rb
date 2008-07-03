require File.dirname(__FILE__) + "/helper"

context "Routes" do
  
  specify "should match explicit paths" do
    event = Sinatra::Event.new(:get, '/foo') {}
    status, _ = event.call(env_for('/foo'))
    assert_equal(200, status)
  end

  specify "should match explicit paths with spaces" do
    event = Sinatra::Event.new(:get, '/foo bar') {}
    status, _ = event.call(env_for('/foo%20bar'))
    assert_equal(200, status)
  end

  specify "should match variables in paths" do
    event = Sinatra::Event.new(:get, '/foo/:bar') {}
    status, _ = event.call(env_for('/foo/baz'))
    assert_equal(200, status)
  end
  
  specify "should expose values of route params" do
    event = Sinatra::Event.new(:get, '/foo/:bar') {}
    status, _ = event.call(env_for('/foo/baz'))
    assert_equal('baz', event.params['bar'])
  end
    
end