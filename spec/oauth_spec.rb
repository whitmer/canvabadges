require File.dirname(__FILE__) + '/spec_helper'

describe 'Badging Models' do
  include Rack::Test::Methods
  
  def app
    Sinatra::Application
  end
  
  describe "POST badge_check" do
  end  
  
  describe "GET oauth_success" do
  end  
end
