require File.dirname(__FILE__) + '/spec_helper'

describe 'Badge Configuration' do
  include Rack::Test::Methods
  
  def app
    Canvabadges
  end

  describe "badge configuration" do
    it "should require instructor/admin authorization" do
      post "/badges/settings/1"
      last_response.should_not be_ok
      assert_error_page("Configuration not found")
      
      post "/badges/settings/1", {}, 'rack.session' => {'user_id' => '1234'}
      last_response.should_not be_ok
      assert_error_page("Configuration not found")
      
      post "/badges/settings/12345", {}, 'rack.session' => {"permission_for_12345" => "view", 'user_id' => '1234'}
      last_response.should_not be_ok
      assert_error_page("Configuration not found")
    end

    it "should accept configuration parameters" do
      badge_config
      params = {
        'badge_url' => "http://example.com/badge.png",
        'badge_name' => "My badge",
        'badge_description' => "My badge description",
        'manual_approval' => '1',
        'min_percent' => '50',
        'module_123' => "Module 123",
        'module_asdf' => "Bad module",
        'credits_for_123' => '19',
        'credit_based' => '1'
      }
      post "/badges/settings/#{@badge_placement_config.id}", params, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => "edit", "user_id" => "9876"}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@badge_placement_config.id}/9876"
      @badge_config.reload
      @badge_placement_config.reload
      @badge_config.settings['badge_url'].should == "http://example.com/badge.png"
      @badge_config.settings['badge_name'].should == "My badge"
      @badge_config.settings['badge_description'].should == "My badge description"
      @badge_placement_config.settings['manual_approval'].should == true
      @badge_placement_config.settings['min_percent'].should == 50.0
      @badge_placement_config.settings['credit_based'].should == true
      @badge_placement_config.credit_based?.should == true
      @badge_placement_config.settings['module_asdf'].should == nil
      @badge_placement_config.settings['modules'].should == [[123, 'Module 123', 19]]
    end
    
    it "should fail gracefully on empty parameters" do
      badge_config
      post "/badges/settings/#{@badge_placement_config.id}", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => "edit", "user_id" => "9876"}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@badge_placement_config.id}/9876"
      @badge_config.reload
      @badge_placement_config.reload
      @badge_config.settings['badge_url'].should == "/badges/default.png"
      @badge_config.settings['badge_name'].should == "Badge"
      @badge_config.settings['badge_description'].should == "No description"
      @badge_placement_config.settings['manual_approval'].should == false
      @badge_placement_config.settings['min_percent'].should == 0.0
      @badge_placement_config.settings['modules'].should == nil
    end
  end  
  
  describe "badge picker" do
    it "should error if not a valid user" do
      example_org
      get "/badges/pick"
      assert_error_page("No user information found")
    end
    
    it "should show matching badges for a valid user" do
      example_org
      user
      badge_config
      @badge_placement_config.author_user_config_id = @user.id
      @badge_placement_config.save
      BadgeConfigOwner.create(:user_config_id => @user.id, :badge_config_id => @badge_config.id, :badge_placement_config_id => @badge_placement_config.id)
      get "/badges/pick", {}, 'rack.session' => {'domain_id' => @badge_placement_config.domain_id, 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should match(@badge_placement_config.badge_config.settings['badge_url'])
      last_response.body.should match(/Create a New Badge/)
    end
  end
  
  describe "disabling badges" do
    it "should do nothing if an invalid badge" do
      example_org
      post "/badges/disable/123"
      last_response.should_not be_ok
      assert_error_page("Configuration not found")
      
      badge_config
      post "/badges/disable/#{@badge_placement_config.id}"
      last_response.should_not be_ok
      assert_error_page("Session information lost")

      user
      post "/badges/disable/#{@badge_placement_config.id}", {}, {'rack.session' => {'user_id' => @user.user_id}}
      last_response.should_not be_ok
      assert_error_page("Insufficient permissions")
    end
    
    it "should require edit permissions" do
      example_org
      user
      badge_config
      post "/badges/disable/#{@badge_placement_config.id}", {}, {'rack.session' => {'user_id' => @user.user_id, "permission_for_#{@badge_placement_config.course_id}" => 'view'}}
      last_response.should_not be_ok
      assert_error_page("Insufficient permissions")
    end
    
    it "should disable the badge if allowed" do
      example_org
      user
      badge_config
      post "/badges/disable/#{@badge_placement_config.id}", {}, {'rack.session' => {'user_id' => @user.user_id, "permission_for_#{@badge_placement_config.course_id}" => 'edit'}}
      last_response.should be_ok
      last_response.body.should == {:disabled => true}.to_json
    end
  end
  
  describe "badge privacy" do
    it "should do nothing if an invalid badge" do
      award_badge(badge_config, user)
      post "/badges/#{@badge.nonce}x", {}, 'rack.session' => {'user_id' => @user.user_id}
      last_response.should_not be_ok
      last_response.body.should == {:error => "invalid badge"}.to_json
    end
    
    it "should not let you change someone else's badge" do
      award_badge(badge_config, user)
      post "/badges/#{@badge.nonce}", {}, 'rack.session' => {'user_id' => "asdf"}
      last_response.should_not be_ok
      last_response.body.should == {:error => "user mismatch"}.to_json
    end
    
    it "should allow setting your badge to public" do
      award_badge(badge_config, user)
      @badge.public.should == nil
      post "/badges/#{@badge.nonce}", {'public' => 'true'}, 'rack.session' => {'user_id' => @user.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['id'].should == @badge.id
      json['public'].should == true
      @badge.reload.public.should == true
    end
    
    it "should allow setting your badge to private" do
      award_badge(badge_config, user)
      @badge.public.should == nil
      post "/badges/#{@badge.nonce}", {'public' => 'true'}, 'rack.session' => {'user_id' => @user.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['id'].should == @badge.id
      json['public'].should == true
      @badge.reload.public.should == true
      post "/badges/#{@badge.nonce}", {'public' => 'false'}, 'rack.session' => {'user_id' => @user.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['id'].should == @badge.id
      json['public'].should == false
      @badge.reload.public.should == false
    end
    
    it "should allow setting the evidence URL for your badge" do
      award_badge(badge_config, user)
      @badge.state = 'pending'
      @badge.save
      @badge.public.should == nil
      post "/badges/#{@badge.nonce}", {'evidence_url' => 'http://www.example.com'}, 'rack.session' => {'user_id' => @user.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['id'].should == @badge.id
      @badge.reload.evidence_url.should == 'http://www.example.com'
      post "/badges/#{@badge.nonce}", {'evidence_url' => 'http://www.google.com'}, 'rack.session' => {'user_id' => @user.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['id'].should == @badge.id
      @badge.reload.evidence_url.should == 'http://www.google.com'
    end
    
    it "should not impact public/private when setting the evidence URL" do
      award_badge(badge_config, user)
      @badge.state = 'pending'
      @badge.public = true
      @badge.save
      post "/badges/#{@badge.nonce}", {'evidence_url' => 'http://www.example.com'}, 'rack.session' => {'user_id' => @user.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['id'].should == @badge.id
      @badge.reload.evidence_url.should == 'http://www.example.com'
      @badge.public.should == true
      post "/badges/#{@badge.nonce}", {'evidence_url' => 'http://www.google.com'}, 'rack.session' => {'user_id' => @user.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['id'].should == @badge.id
      @badge.reload.evidence_url.should == 'http://www.google.com'
      @badge.public.should == true
    end
    
    it "should not allow setting the evidence URL for an already-awarded badge" do
      award_badge(badge_config, user)
      @badge.state.should == 'awarded'
      @badge.evidence_url.should == nil
      
      post "/badges/#{@badge.nonce}", {'evidence_url' => 'http://www.example.com'}, 'rack.session' => {'user_id' => @user.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['id'].should == @badge.id
      @badge.reload.evidence_url.should == nil
    end
  end
  
  describe "manually awarding badges" do
    it "should require instructor/admin authorization" do
      badge_config
      user
      post "/badges/award/#{@badge_placement_config.id}/#{@user.user_id}", {}, 'rack.session' => {}
      last_response.should_not be_ok
      assert_error_page("Session information lost")
    end
    
    it "should do nothing for an invalid course or user" do
      badge_config
      post "/badges/award/#{@badge_placement_config.id}/asdfjkl", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit'}
      last_response.should_not be_ok
      assert_error_page("Session information lost")

      post "/badges/award/asdf/asdfjkl", {}, 'rack.session' => {'permission_for_asdf' => 'edit', 'user_id' => 'asdf'}
      last_response.should_not be_ok
      assert_error_page("Configuration not found")
      

      post "/badges/award/#{@badge_placement_config.id}/asdfjkl", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => 'asdf'}
      last_response.should_not be_ok
      assert_error_page("This badge has not been configured yet")
      
      @badge_placement_config.settings['min_percent'] = 10
      @badge_placement_config.save
      Canvabadges.any_instance.should_receive(:api_call).and_return([])

      post "/badges/award/#{@badge_placement_config.id}/asdfjkl", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => 'asdf'}
      last_response.should_not be_ok
      assert_error_page("That user is not a student in this course")
    end
    
    it "should fail on manual awarding if no email provided by api" do
      user
      configured_badge
      Canvabadges.any_instance.should_receive(:api_call).and_return([{'id' => @user.user_id.to_i, 'name' => 'bob'}])
      post "/badges/award/#{@badge_placement_config.id}/#{@user.user_id}", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should_not be_redirect
      assert_error_page("That user doesn't have an email in Canvas")
    end
    
    it "should allow manual awarding" do
      user
      configured_badge
      Canvabadges.any_instance.should_receive(:api_call).and_return([{'id' => @user.user_id.to_i, 'name' => 'bob', 'email' => 'bob@example.com'}])
      post "/badges/award/#{@badge_placement_config.id}/#{@user.user_id}", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@badge_placement_config.id}/#{@user.user_id}"
    end
    
    it "should allow instructors to manually award the badge for their students" do
      badge_config
      user
      @badge_placement_config.settings['min_percent'] = 10
      @badge_placement_config.save
      Canvabadges.any_instance.should_receive(:api_call).and_return([{'id' => @user.user_id.to_i, 'name' => 'bob', 'email' => 'bob@example.com'}])
      post "/badges/award/#{@badge_placement_config.id}/#{@user.user_id}", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@badge_placement_config.id}/#{@user.user_id}"
    end
  end
end
