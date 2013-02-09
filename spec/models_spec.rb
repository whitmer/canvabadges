require File.dirname(__FILE__) + '/spec_helper'

describe 'Badging Models' do
  include Rack::Test::Methods
  
  def app
    Sinatra::Application
  end
  
  describe "UserConfig model" do
    it "should return 'host' from the domain model"
    it "should fail gracefully if no host specified"
  end  
  
  describe "CourseConfig model" do
    it "should generate nonce on save"

    describe "root configuration" do
      it "should allow setting root config from ref code"
      it "should not fail if root isn't found"
      it "should pull settings from root config if set"
      it "should return current config if no root config set"
      it "should pull nonce from root config if set"
      it "should return current nonce if no root config set"
    end
    
    describe "configuration options" do
      it "should check if actually configured"
      it "check if modules are required"
      it "should return list of required modules"
      it "should check if requirements are met"
    end
    
  end  
  
  describe "Badge model" do
    describe "OBI badge JSON" do
    end
    
    it "should generate defaults on save"
    it "should return valid user name"
    it "should return valid course nonce"
    it "should allow generating badges"
    it "should allow manually awarding new badges"
    it "should allow manually awarding existing badges"
    it "should allow completing new badges"
    it "should allow completing existing badges"
  end  
  
end
