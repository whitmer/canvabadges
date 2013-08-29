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
        'reference_code' => "12345678",
        'badge_description' => "My badge description",
        'manual_approval' => '1',
        'min_percent' => '50',
        'module_123' => "Module 123",
        'module_asdf' => "Bad module",
        'credits_for_123' => '19',
        'credit_based' => '1'
      }
      post "/badges/settings/#{@badge_config.id}", params, 'rack.session' => {"permission_for_#{@badge_config.course_id}" => "edit", "user_id" => "9876"}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@badge_config.id}/9876"
      @badge_config.reload
      @badge_config.settings['badge_url'].should == "http://example.com/badge.png"
      @badge_config.settings['badge_name'].should == "My badge"
      @badge_config.settings['reference_code'].should == '12345678'
      @badge_config.settings['badge_description'].should == "My badge description"
      @badge_config.settings['manual_approval'].should == true
      @badge_config.settings['min_percent'].should == 50.0
      @badge_config.settings['credit_based'].should == true
      @badge_config.credit_based?.should == true
      @badge_config.settings['module_asdf'].should == nil
      @badge_config.settings['modules'].should == [[123, 'Module 123', 19]]
    end
    
    it "should fail gracefully on empty parameters" do
      badge_config
      post "/badges/settings/#{@badge_config.id}", {}, 'rack.session' => {"permission_for_#{@badge_config.course_id}" => "edit", "user_id" => "9876"}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@badge_config.id}/9876"
      @badge_config.reload
      @badge_config.settings['badge_url'].should == "/badges/default.png"
      @badge_config.settings['badge_name'].should == "Badge"
      @badge_config.settings['reference_code'].should == nil
      @badge_config.settings['badge_description'].should == "No description"
      @badge_config.settings['manual_approval'].should == false
      @badge_config.settings['min_percent'].should == 0.0
      @badge_config.settings['modules'].should == nil
    end
    
    it "should allow linking to an existing badge" do
      @bc1 = badge_config
      @bc2 = badge_config
      post "/badges/settings/#{@bc2.id}", {'reference_code' => @bc1.reference_code}, 'rack.session' => {"permission_for_#{@bc2.course_id}" => "edit", "user_id" => "9876"}
      
      @bc1.id.should_not == @bc2.id
      @bc2.root_nonce.should == @bc1.nonce
      @bc2.root_settings.should == @bc1.settings

      @bc3 = badge_config
      post "/badges/settings/#{@bc3.id}", {'reference_code' => ''}, 'rack.session' => {"permission_for_#{@bc3.course_id}" => "edit", "user_id" => "9876"}
      @bc3.id.should_not == @bc1.id
      @bc3.root_nonce.should == @bc3.nonce
      @bc3.root_settings.should == @bc3.settings
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
      post "/badges/award/#{@badge_config.id}/#{@user.user_id}", {}, 'rack.session' => {}
      last_response.should_not be_ok
      assert_error_page("Session information lost")
    end
    
    it "should do nothing for an invalid course or user" do
      badge_config
      post "/badges/award/#{@badge_config.id}/asdfjkl", {}, 'rack.session' => {"permission_for_#{@badge_config.course_id}" => 'edit'}
      last_response.should_not be_ok
      assert_error_page("Session information lost")

      post "/badges/award/asdf/asdfjkl", {}, 'rack.session' => {'permission_for_asdf' => 'edit', 'user_id' => 'asdf'}
      last_response.should_not be_ok
      assert_error_page("Configuration not found")
      

      post "/badges/award/#{@badge_config.id}/asdfjkl", {}, 'rack.session' => {"permission_for_#{@badge_config.course_id}" => 'edit', 'user_id' => 'asdf'}
      last_response.should_not be_ok
      assert_error_page("This badge has not been configured yet")
      
      @badge_config.settings['min_percent'] = 10
      @badge_config.save
      Canvabadges.any_instance.should_receive(:api_call).and_return([])

      post "/badges/award/#{@badge_config.id}/asdfjkl", {}, 'rack.session' => {"permission_for_#{@badge_config.course_id}" => 'edit', 'user_id' => 'asdf'}
      last_response.should_not be_ok
      assert_error_page("That user is not a student in this course")
    end
    
    it "should fail on manual awarding if no email provided by api" do
      user
      configured_badge
      Canvabadges.any_instance.should_receive(:api_call).and_return([{'id' => @user.user_id.to_i, 'name' => 'bob'}])
      post "/badges/award/#{@badge_config.id}/#{@user.user_id}", {}, 'rack.session' => {"permission_for_#{@badge_config.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should_not be_redirect
      assert_error_page("That user doesn't have an email in Canvas")
    end
    
    it "should allow manual awarding" do
      user
      configured_badge
      Canvabadges.any_instance.should_receive(:api_call).and_return([{'id' => @user.user_id.to_i, 'name' => 'bob', 'email' => 'bob@example.com'}])
      post "/badges/award/#{@badge_config.id}/#{@user.user_id}", {}, 'rack.session' => {"permission_for_#{@badge_config.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@badge_config.id}/#{@user.user_id}"
    end
    
    it "should allow instructors to manually award the badge for their students" do
      badge_config
      user
      @badge_config.settings['min_percent'] = 10
      @badge_config.save
      Canvabadges.any_instance.should_receive(:api_call).and_return([{'id' => @user.user_id.to_i, 'name' => 'bob', 'email' => 'bob@example.com'}])
      post "/badges/award/#{@badge_config.id}/#{@user.user_id}", {}, 'rack.session' => {"permission_for_#{@badge_config.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@badge_config.id}/#{@user.user_id}"
    end
  end
end
