require File.dirname(__FILE__) + '/spec_helper'
require 'ostruct'

describe 'Badging OAuth' do
  include Rack::Test::Methods
  
  def app
    Canvabadges
  end
  
  describe "POST badge_check" do
    it "should fail on invalid signature" do
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(false)
      post "/placement_launch", {}
      last_response.should_not be_ok
      assert_error_page("Invalid tool launch - unknown tool consumer")
    end
    
    it "should succeed on valid signature" do
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      post "/placement_launch", {'oauth_consumer_key' => '123'}
      last_response.should_not be_ok
      assert_error_page("Course must be a Canvas course, and launched with public permission settings")

      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'custom_canvas_user_id' => '1', 'custom_canvas_course_id' => '1', 'resource_link_id' => 'q2w3e4'}
      last_response.should be_redirect
      bc = BadgeConfig.last
      bc.placement_id.should == 'q2w3e4'
      bc.course_id.should == '1'
      bc.domain_id.should == @domain.id
    end
    
    it "should set session parameters" do
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'custom_canvas_user_id' => '1', 'custom_canvas_course_id' => '1'}
      last_response.should be_redirect
      session['user_id'].should == '1'
      session['launch_course_id'].should == '1'
      session['permission_for_1'].should == 'view'
      session['email'].should == nil
      session['source_id'].should == 'cloud'
      session['name'].should == nil
      session['domain_id'].should == @domain.id.to_s
    end
    
    it "should provision domain if new" do
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      Domain.last.host.should_not == 'bob.org'
      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.org', 'custom_canvas_user_id' => '1', 'custom_canvas_course_id' => '1'}
      last_response.should be_redirect
      Domain.last.host.should == 'bob.org'
    end
    
    it "should redirect to oauth if not authorized" do
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'custom_canvas_user_id' => '1', 'custom_canvas_course_id' => '1'}
      last_response.should be_redirect
      last_response.location.should == "https://bob.com/login/oauth2/auth?client_id=abc&response_type=code&redirect_uri=https%3A%2F%2Fexample.org%2Foauth_success"
    end
    
    it "should redirect to badge page if authorized" do
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      user
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1'}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@domain.id}/2s3d/#{@user.user_id}"
    end
    
  end  
  
  describe "GET oauth_success" do
    it "should error if session details are not preserved" do
      get "/oauth_success"
      assert_error_page("Launch parameters lost")
    end
      
    it "should error if token cannot be properly exchanged" do
      user
      fake_response = OpenStruct.new(:body => {}.to_json)
      Net::HTTP.any_instance.should_receive(:request).and_return(fake_response)
      get "/oauth_success?code=asdfjkl", {}, 'rack.session' => {"domain_id" => @domain.id, 'user_id' => @user.user_id, 'source_id' => 'cloud', 'launch_placement_id' => 'uiop'}
      assert_error_page("Error retrieving access token")
    end
    
    it "should provision a new user if successful" do
      fake_response = OpenStruct.new(:body => {:access_token => '1234', 'user' => {'id' => 'zxcv'}}.to_json)
      Net::HTTP.any_instance.should_receive(:request).and_return(fake_response)
      get "/oauth_success?code=asdfjkl", {}, 'rack.session' => {"domain_id" => @domain.id, 'user_id' => 'fghj', 'source_id' => 'cloud', 'launch_placement_id' => 'uiop'}
      @user = UserConfig.last
      @user.should_not be_nil
      @user.user_id.should == 'fghj'
      @user.domain_id.should == @domain.id
      @user.access_token.should == '1234'
      session['user_id'].should == @user.user_id
      session['domain_id'].should == @domain.id
    end
    
    it "should update an existing user if successful" do
      user
      fake_response = OpenStruct.new(:body => {:access_token => '1234', 'user' => {'id' => 'zxcv'}}.to_json)
      Net::HTTP.any_instance.should_receive(:request).and_return(fake_response)
      get "/oauth_success?code=asdfjkl", {}, 'rack.session' => {"domain_id" => @domain.id, 'user_id' => @user.user_id, 'source_id' => 'cloud', 'launch_placement_id' => 'uiop'}
      @new_user = UserConfig.last
      @new_user.should_not be_nil
      @new_user.id.should == @user.id
      session['user_id'].should == @user.user_id
      session['domain_id'].should == @domain.id
    end
    
    it "should redirect to the badge check endpoint if successful" do
      fake_response = OpenStruct.new(:body => {:access_token => '1234', 'user' => {'id' => 'zxcv'}}.to_json)
      Net::HTTP.any_instance.should_receive(:request).and_return(fake_response)
      get "/oauth_success?code=asdfjkl", {}, 'rack.session' => {"domain_id" => @domain.id, 'user_id' => 'fghj', 'source_id' => 'cloud', 'launch_placement_id' => 'uiop'}
      @user = UserConfig.last
      @user.user_id.should == 'fghj'
      @user.domain_id.should == @domain.id
      @user.access_token.should == '1234'
      session['user_id'].should == @user.user_id
      session['domain_id'].should == @domain.id
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@domain.id}/uiop/#{@user.user_id}"
    end
  end  
end
