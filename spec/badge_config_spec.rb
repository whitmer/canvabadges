require File.dirname(__FILE__) + '/spec_helper'

describe 'Badge Configuration' do
  include Rack::Test::Methods
  
  def app
    Sinatra::Application
  end

  describe "badge configuration" do
    it "should require instructor/admin authorization"
    it "should do nothing for an invalid course"
    it "should accept configuration parameters"
    it "should fail gracefully on empty parameters"
    it "should allow linking to an existing badge"
  end  
  
  describe "badge privacy" do
    it "should do nothing if an invalid badge"
    it "should not let you change someone else's badge"
    it "should allow setting your badge to public"
    it "should allow setting your badge to private"
  end
  
  describe "manually awarding badges" do
    it "should require instructor/admin authorization"
    it "should do nothing for an invalid course or user"
    it "should allow instructors to manually award the badge for their students"
  end
end
