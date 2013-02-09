require File.dirname(__FILE__) + '/spec_helper'

describe 'Badging Models' do
  include Rack::Test::Methods
  
  def app
    Sinatra::Application
  end
  
  describe "index" do
    it "should return"
  end  
  
  describe "LTI XML config" do
    it "should return valid LTI configuration"
  end  
  
  describe "public badge page" do
    it "should fail gracefully if invalid nonce provided"
    it "should return badge completion requirements for valid bage"
  end  
  
  describe "public badges for user" do
    it "should fail gracefully for invalid domain or user id"
    it "should return badge completion/publicity information for the current user"
    it "should return badge summary for someone other than the current user"
  end  
  
  describe "badge launch page" do
    it "should fail gracefully on invalid course, user or domain parameters"
    it "should allow instructors/admins to configure unconfigured badges"
    it "should not allow students to see unconfigured badges"
    it "should check completion information if the current user is a student"
    
    describe "meeting completion criteria as a student" do
      it "should award the badge if final grade is the only criteria and is met"
      it "should not award the badge if final grade criteria is not met"
      it "should award the badge if final grade and module completions are met"
      it "should not award the badge if final grade is met but not module completions"
    end
  end    
end
