require File.dirname(__FILE__) + '/spec_helper'
require 'ostruct'

describe 'Badging OAuth' do
  include Rack::Test::Methods
  
  def app
    Canvabadges
  end
  
  describe "POST badge_check" do
    it "should fail when missing org config" do
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(false)
      post "/placement_launch", {}
      last_response.should_not be_ok
      assert_error_page("Domain not properly configured.")
    end
    

    it "should fail on invalid signature" do
      example_org
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(false)
      post "/placement_launch", {}
      last_response.should_not be_ok
      assert_error_page("Invalid tool launch - unknown tool consumer")
    end
    
    it "should succeed on valid signature" do
      example_org
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      post "/placement_launch", {'oauth_consumer_key' => '123', 'lis_person_contact_email_primary' => 'bob@example.com'}
      last_response.should_not be_ok
      assert_error_page("App must be launched with public permission settings.")

      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'custom_canvas_user_id' => '1', 'custom_canvas_course_id' => '1', 'resource_link_id' => 'q2w3e4', 'lis_person_contact_email_primary' => 'bob@example.com'}
      last_response.should be_redirect
      bc = BadgePlacementConfig.last
      bc.placement_id.should == 'q2w3e4'
      bc.course_id.should == '1'
      bc.domain_id.should == @domain.id
    end
    
    it "should set session parameters" do
      example_org
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'custom_canvas_user_id' => '1', 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
      last_response.should be_redirect
      session['user_id'].should == '1'
      session['launch_course_id'].should == '1'
      session['permission_for_1'].should == 'view'
      session['email'].should == 'bob@example.com'
      session['source_id'].should == 'cloud'
      session['name'].should == nil
      session['domain_id'].should == @domain.id.to_s
    end
    
    it "should provision domain if new" do
      example_org
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      Domain.last.host.should_not == 'bob.org'
      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.org', 'custom_canvas_user_id' => '1', 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
      last_response.should be_redirect
      Domain.last.host.should == 'bob.org'
    end
    
    it "should tie badge config to the current organization" do
      example_org
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      Domain.last.host.should_not == 'bob.org'
      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.org', 'custom_canvas_user_id' => '1', 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
      last_response.should be_redirect
      BadgeConfig.last.organization_id.should == @org.id
      BadgePlacementConfig.last.organization_id.should == @org.id
    end
    
    it "should tie badge config to a different organization if specified" do
      example_org
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.org', 'custom_canvas_user_id' => '1', 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
      last_response.should be_redirect
      BadgeConfig.last.organization_id.should == @org.id
      BadgePlacementConfig.last.organization_id.should == @org.id
    end
    
    it "should redirect to oauth if not authorized" do
      example_org
      @org2 = Organization.create(:host => "bob.com", :settings => {'name' => 'my org'})
      ExternalConfig.create(:config_type => 'lti', :value => '123', :organization_id => @org2.id)
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'custom_canvas_user_id' => '1', 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
      last_response.should be_redirect
      last_response.location.should == "https://bob.com/login/oauth2/auth?client_id=abc&response_type=code&redirect_uri=https%3A%2F%2Fexample.org%2Foauth_success"
      BadgeConfig.last.organization_id.should == @org2.id
      BadgePlacementConfig.last.organization_id.should == @org2.id
    end
    
    it "should redirect to oauth if authorized but bad API response" do
      example_org
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      user
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      CanvasAPI.should_receive(:api_call).and_return({})
      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
      last_response.should be_redirect
      last_response.location.should == "https://bob.com/login/oauth2/auth?client_id=abc&response_type=code&redirect_uri=https%3A%2F%2Fexample.org%2Foauth_success"
    end
    
    it "should redirect to badge page if authorized" do
      example_org
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      user
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
      post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
      last_response.should be_redirect
      bc = BadgePlacementConfig.last
      last_response.location.should == "http://example.org/badges/check/#{bc.id}/#{@user.user_id}"
    end
    
    it "should redirect to user page if specified" do
      example_org
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      user
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
      post "/placement_launch", {'custom_show_all' => '1', 'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
      last_response.should be_redirect
      d = Domain.last
      last_response.location.should == "http://example.org/badges/all/#{d.id}/#{@user.user_id}"
      
      get "/badges/all/#{d.id}/#{@user.user_id}"
      last_response.body.should match(/Your Badges/)
    end
    
    it "should redirect to picker page if specified" do
      example_org
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      user
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
      post "/placement_launch", {'ext_content_intended_use' => 'navigation', 'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com', 'launch_presentation_return_url' => 'http://www.example.com'}
      last_response.should be_redirect
      BadgePlacementConfig.last.should be_nil
      last_response.location.should == "http://example.org/badges/pick?return_url=http%3A%2F%2Fwww.example.com"
    end
    
    it "should redirect to course page if specified" do
      example_org
      ExternalConfig.create(:config_type => 'lti', :value => '123')
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      user
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
      CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
      post "/placement_launch", {'custom_show_course' => '1', 'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com', 'launch_presentation_return_url' => 'http://www.example.com'}
      last_response.should be_redirect
      BadgePlacementConfig.last.should be_nil
      last_response.location.should == "http://example.org/badges/course/1"
    end
    
    describe "loading from existing badge" do
      it "should do nothing on an invalid badge config id" do
        example_org
        ExternalConfig.create(:config_type => 'lti', :value => '123')
        ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
        user
        IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
        IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
        CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
        post "/placement_launch", {'badge_reuse_code' => 'abc123', 'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
        last_response.should be_redirect
        bc = BadgePlacementConfig.last
        bc.badge_config.should == BadgeConfig.last
        last_response.location.should == "http://example.org/badges/check/#{bc.id}/#{@user.user_id}"
      end
      
      it "should do nothing when the badge config id is for a different organization" do
        @org1 = example_org
        @org2 = configured_school
        BadgeConfig.create(:organization_id => @org2.id, :reuse_code => 'abc123')
        
        ExternalConfig.create(:config_type => 'lti', :value => '123')
        ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
        user
        IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
        IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
        CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
        post "/placement_launch", {'badge_reuse_code' => 'abc123', 'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
        last_response.should be_redirect
        bc = BadgePlacementConfig.last
        bc.badge_config.should == BadgeConfig.last
        last_response.location.should == "http://example.org/badges/check/#{bc.id}/#{@user.user_id}"
      end
      
      it "should link to the existing badge when the badge config id is for the same organization" do
        example_org
        @bc = BadgeConfig.create(:organization_id => @org.id, :reuse_code => 'abc123')
        
        ExternalConfig.create(:config_type => 'lti', :value => '123')
        ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
        user
        IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
        IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
        CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
        post "/placement_launch", {'badge_reuse_code' => 'abc123', 'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
        last_response.should be_redirect
        bc = BadgePlacementConfig.last
        bc.badge_config.should == @bc
        last_response.location.should == "http://example.org/badges/check/#{bc.id}/#{@user.user_id}"
      end
      
      it "should set the prior link id for reusing course settings when the badge config id is for the same organization" do
        example_org
        configured_badge
        @badge_config.reuse_code = 'abc123'
        @badge_config.save
        
        ExternalConfig.create(:config_type => 'lti', :value => '123')
        ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
        user
        IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
        IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
        CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
        post "/placement_launch", {'badge_reuse_code' => 'abc123', 'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
        last_response.should be_redirect
        bc = BadgePlacementConfig.last
        bc.should_not == @badge_placement_config
        bc.badge_config.should == @badge_config
        bc.settings['prior_resource_link_id'].should == @badge_placement_config.placement_id
        bc.settings['pending'].should == true
        last_response.location.should == "http://example.org/badges/check/#{bc.id}/#{@user.user_id}"
      end
      
      it "should not link to the existing badge when the current badge is already configured" do
        example_org
        @bc = BadgeConfig.create(:organization_id => @org.id, :reuse_code => 'abc123')
        configured_badge
        
        ExternalConfig.create(:config_type => 'lti', :value => '123')
        ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
        user
        IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
        IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
        CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
        post "/placement_launch", {'badge_reuse_code' => 'abc123', 'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => @badge_placement_config.placement_id, 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => @badge_placement_config.course_id, 'lis_person_contact_email_primary' => 'bob@example.com'}
        last_response.should be_redirect
        bc = BadgePlacementConfig.last
        bc.badge_config.should_not == @bc
        last_response.location.should == "http://example.org/badges/check/#{bc.id}/#{@user.user_id}"
      end
      
      
      it "should 'migrate' up to the new model scheme when an 'old' badge config is launched" do
        example_org
        @bc = old_school_configured_badge

        ExternalConfig.create(:config_type => 'lti', :value => '123')
        ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
        user
        IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
        IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
        CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
        post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => @bc.placement_id, 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => @bc.course_id, 'lis_person_contact_email_primary' => 'bob@example.com'}
        last_response.should be_redirect
        bpc = BadgePlacementConfig.last
        bpc.badge_config.should == @bc
        bpc.settings['min_percent'].should_not be_nil
        bpc.settings['modules'].should_not be_nil
        bpc.settings['credit_based'].should == true
        bpc.placement_id.should == @bc.placement_id
        last_response.location.should == "http://example.org/badges/check/#{bpc.id}/#{@user.user_id}"
      end

      it "should not migrate up once the badge has already been migrated" do
        example_org
        @bc = old_school_configured_badge
        @bpc = BadgePlacementConfig.create(:placement_id => @bc.placement_id, :course_id => @bc.course_id, :domain_id => @bc.domain_id)
        @bpc.set_badge_config(@bc)
        @bpc.settings['credit_based'] = false
        @bpc.save

        ExternalConfig.create(:config_type => 'lti', :value => '123')
        ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
        user
        IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
        IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
        CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
        post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => @bc.placement_id, 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => @bc.course_id, 'lis_person_contact_email_primary' => 'bob@example.com'}
        last_response.should be_redirect
        bpc = BadgePlacementConfig.last
        bpc.should == @bpc
        bpc.badge_config.should == @bc
        bpc.settings['min_percent'].should_not be_nil
        bpc.settings['modules'].should_not be_nil
        bpc.settings['credit_based'].should == false
        bpc.placement_id.should == @bc.placement_id
        last_response.location.should == "http://example.org/badges/check/#{bpc.id}/#{@user.user_id}"
      end
      
      it "should create a new badge config for the placement if one is not already linked" do
        example_org
        ExternalConfig.create(:config_type => 'lti', :value => '123')
        ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
        user
        IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
        IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['student'])
        CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
        post "/placement_launch", {'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
        last_response.should be_redirect
        bpc = BadgePlacementConfig.last
        last_response.location.should == "http://example.org/badges/check/#{bpc.id}/#{@user.user_id}"
        bc = BadgeConfig.last
        bc.should_not == nil
        bpc.badge_config.should == bc
      end
    end
  end  
  
  describe "GET oauth_success" do
    it "should error if session details are not preserved" do
      get "/oauth_success"
      assert_error_page("Session Information Lost")
    end
      
    it "should error if token cannot be properly exchanged" do
      example_org
      user
      fake_response = OpenStruct.new(:body => {}.to_json)
      Net::HTTP.any_instance.should_receive(:request).and_return(fake_response)
      get "/oauth_success?code=asdfjkl", {}, 'rack.session' => {"domain_id" => @domain.id, 'user_id' => @user.user_id, 'source_id' => 'cloud', 'launch_badge_placement_config_id' => 'uiop'}
      assert_error_page("Error retrieving access token")
    end
    
    it "should provision a new user if successful" do
      example_org
      fake_response = OpenStruct.new(:body => {:access_token => '1234', 'user' => {'id' => 'zxcv'}}.to_json)
      Net::HTTP.any_instance.should_receive(:request).and_return(fake_response)
      get "/oauth_success?code=asdfjkl", {}, 'rack.session' => {"domain_id" => @domain.id, 'user_id' => 'fghj', 'source_id' => 'cloud', 'launch_badge_placement_config_id' => 'uiop'}
      @user = UserConfig.last
      @user.should_not be_nil
      @user.user_id.should == 'fghj'
      @user.domain_id.should == @domain.id
      @user.access_token.should == '1234'
      session['user_id'].should == @user.user_id
      session['domain_id'].should == @domain.id
    end
    
    it "should update an existing user if successful" do
      example_org
      user
      fake_response = OpenStruct.new(:body => {:access_token => '1234', 'user' => {'id' => 'zxcv'}}.to_json)
      Net::HTTP.any_instance.should_receive(:request).and_return(fake_response)
      get "/oauth_success?code=asdfjkl", {}, 'rack.session' => {"domain_id" => @domain.id, 'user_id' => @user.user_id, 'source_id' => 'cloud', 'launch_badge_placement_config_id' => 'uiop'}
      @new_user = UserConfig.last
      @new_user.should_not be_nil
      @new_user.id.should == @user.id
      session['user_id'].should == @user.user_id
      session['domain_id'].should == @domain.id
    end
    
    it "should redirect to the badge check endpoint if successful" do
      example_org
      fake_response = OpenStruct.new(:body => {:access_token => '1234', 'user' => {'id' => 'zxcv'}}.to_json)
      Net::HTTP.any_instance.should_receive(:request).and_return(fake_response)
      get "/oauth_success?code=asdfjkl", {}, 'rack.session' => {"domain_id" => @domain.id, 'user_id' => 'fghj', 'source_id' => 'cloud', 'launch_badge_placement_config_id' => 'uiop'}
      @user = UserConfig.last
      @user.user_id.should == 'fghj'
      @user.domain_id.should == @domain.id
      @user.access_token.should == '1234'
      session['user_id'].should == @user.user_id
      session['domain_id'].should == @domain.id
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/uiop/#{@user.user_id}"
    end
    
    it "should redirect to user page if specified" do
      example_org
      user
      ExternalConfig.create(:config_type => 'lti', :value => '123', :organization_id => @org.id)
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['instructor'])
      CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
      post "/placement_launch", {'custom_show_all' => '1', 'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com'}
      last_response.should be_redirect

      fake_response = OpenStruct.new(:body => {:access_token => '1234', 'user' => {'id' => 'zxcv'}}.to_json)
      Net::HTTP.any_instance.should_receive(:request).and_return(fake_response)
      get_with_session "/oauth_success?code=asdfjkl"
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/all/1/#{@user.user_id}"
    end
    
    it "should redirect to picker page if specified" do
      example_org
      user
      ExternalConfig.create(:config_type => 'lti', :value => '123', :organization_id => @org.id)
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['instructor'])
      CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
      post "/placement_launch", {'ext_content_intended_use' => 'navigation', 'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com', 'launch_presentation_return_url' => 'http://www.example.com'}
      last_response.should be_redirect

      fake_response = OpenStruct.new(:body => {:access_token => '1234', 'user' => {'id' => 'zxcv'}}.to_json)
      Net::HTTP.any_instance.should_receive(:request).and_return(fake_response)
      get "/oauth_success?code=asdfjkl", {}, 'rack.session' => session
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/pick?return_url=#{CGI.escape("http://www.example.com")}"
    end
    
    it "should redirect to course page if specified" do
      example_org
      user
      ExternalConfig.create(:config_type => 'lti', :value => '123', :organization_id => @org.id)
      ExternalConfig.create(:config_type => 'canvas_oauth', :value => '456')
      IMS::LTI::ToolProvider.any_instance.stub(:valid_request?).and_return(true)
      IMS::LTI::ToolProvider.any_instance.stub(:roles).and_return(['instructor'])
      CanvasAPI.should_receive(:api_call).and_return({'id' => '123'})
      post "/placement_launch", {'custom_show_course' => '1', 'oauth_consumer_key' => '123', 'tool_consumer_instance_guid' => 'something.bob.com', 'resource_link_id' => '2s3d', 'custom_canvas_user_id' => @user.user_id, 'custom_canvas_course_id' => '1', 'lis_person_contact_email_primary' => 'bob@example.com', 'launch_presentation_return_url' => 'http://www.example.com'}
      last_response.should be_redirect

      fake_response = OpenStruct.new(:body => {:access_token => '1234', 'user' => {'id' => 'zxcv'}}.to_json)
      Net::HTTP.any_instance.should_receive(:request).and_return(fake_response)
      get "/oauth_success?code=asdfjkl", {}, 'rack.session' => session
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/course/1"
    end
  end  
  
  describe "oauth_config" do
    it "should raise if no config is found" do
      ExternalConfig.first(:config_type => 'canvas_oauth').destroy
      expect { OAuthConfig.oauth_config }.to raise_error("Missing oauth config")
    end
    
    it "should return the default config if no org is found" do
      example_org
      c = ExternalConfig.create(:organization_id => @org.id + 1, :config_type => 'canvas_oss_oauth', :value => 'abc', :shared_secret => 'xyz')
      OAuthConfig.oauth_config(@org).should == ExternalConfig.first(:config_type => 'canvas_oauth')
    end
    it "should return the org-specific config if found" do
      example_org
      c = ExternalConfig.create(:organization_id => @org.id, :config_type => 'canvas_oss_oauth', :value => 'abc', :shared_secret => 'xyz')
      OAuthConfig.oauth_config(@org).should == ExternalConfig.first(:config_type => 'canvas_oauth')
      @org.settings['oss_oauth'] = true
      @org.save
      OAuthConfig.oauth_config(@org).should == c
    end
  end
  
  describe "session fix" do
    it "should set session" do
      get "/session_fix"
      last_response.body.should match(/Session Fixer/)
      session['has_session'].should == true
    end
  end
end
