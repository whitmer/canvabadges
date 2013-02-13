require File.dirname(__FILE__) + '/spec_helper'

describe 'Badge Configuration' do
  include Rack::Test::Methods
  
  def app
    Sinatra::Application
  end

  describe "badge configuration" do
    it "should require instructor/admin authorization" do
      post "/badges/settings/1/00"
      last_response.should be_ok
      assert_error_page("Session information lost")
      
      post "/badges/settings/1/00", {}, 'rack.session' => {'user_id' => '1234'}
      last_response.should be_ok
      assert_error_page("You can't edit this")
      
      post "/badges/settings/#{@domain.id}/12345", {}, 'rack.session' => {"permission_for_12345" => "view", 'user_id' => '1234'}
      last_response.should be_ok
      assert_error_page("You can't edit this")
    end

    it "should accept configuration parameters" do
      params = {
        'badge_url' => "http://example.com/badge.png",
        'badge_name' => "My badge",
        'reference_code' => "12345678",
        'badge_description' => "My badge description",
        'manual_approval' => '1',
        'min_percent' => '50',
        'module_123' => "Module 123",
        'module_asdf' => "Bad module"
      }
      post "/badges/settings/#{@domain.id}/12345", params, 'rack.session' => {"permission_for_12345" => "edit", "user_id" => "9876"}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@domain.id}/12345/9876"
      course = CourseConfig.last
      course.course_id.should == '12345'
      course.settings['badge_url'].should == "http://example.com/badge.png"
      course.settings['badge_name'].should == "My badge"
      course.settings['reference_code'].should == '12345678'
      course.settings['badge_description'].should == "My badge description"
      course.settings['manual_approval'].should == true
      course.settings['min_percent'].should == 50.0
      course.settings['modules'].should == [[123, 'Module 123']]
      
    end
    
    it "should fail gracefully on empty parameters" do
      post "/badges/settings/#{@domain.id}/12345", {}, 'rack.session' => {"permission_for_12345" => "edit", "user_id" => "9876"}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@domain.id}/12345/9876"
      course = CourseConfig.last
      course.course_id.should == '12345'
      course.settings['badge_url'].should == "/badges/default.png"
      course.settings['badge_name'].should == "Badge"
      course.settings['reference_code'].should == nil
      course.settings['badge_description'].should == "No description"
      course.settings['manual_approval'].should == false
      course.settings['min_percent'].should == 0.0
      course.settings['modules'].should == nil
    end
    
    it "should allow linking to an existing badge" do
      course
      post "/badges/settings/#{@domain.id}/12345", {'reference_code' => @course.reference_code}, 'rack.session' => {"permission_for_12345" => "edit", "user_id" => "9876"}
      course = CourseConfig.last
      course.id.should_not == @course.id
      course.root_nonce.should == @course.nonce
      course.root_settings.should == @course.settings

      course
      post "/badges/settings/#{@domain.id}/12345", {'reference_code' => ''}, 'rack.session' => {"permission_for_12345" => "edit", "user_id" => "9876"}
      course = CourseConfig.last
      course.id.should_not == @course.id
      course.root_nonce.should == course.nonce
      course.root_settings.should == course.settings
    end
  end  
  
  describe "badge privacy" do
    it "should do nothing if an invalid badge" do
      award_badge(course, user)
      post "/badges/#{@badge.nonce}x", {}, 'rack.session' => {'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should == {:error => "invalid badge"}.to_json
    end
    
    it "should not let you change someone else's badge" do
      award_badge(course, user)
      post "/badges/#{@badge.nonce}", {}, 'rack.session' => {'user_id' => "asdf"}
      last_response.should be_ok
      last_response.body.should == {:error => "user mismatch"}.to_json
    end
    
    it "should allow setting your badge to public" do
      award_badge(course, user)
      @badge.public.should == nil
      post "/badges/#{@badge.nonce}", {'public' => 'true'}, 'rack.session' => {'user_id' => @user.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['id'].should == @badge.id
      json['public'].should == true
      @badge.reload.public.should == true
    end
    
    it "should allow setting your badge to private" do
      award_badge(course, user)
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
  end
  
  describe "manually awarding badges" do
    it "should require instructor/admin authorization" do
      course
      user
      post "/badges/award/#{@domain.id}/#{@course.course_id}/#{@user.user_id}", {}, 'rack.session' => {}
      last_response.should be_ok
      assert_error_page("You don't have permission to award this badge")
    end
    
    it "should do nothing for an invalid course or user" do
      course
      post "/badges/award/#{@domain.id}/#{@course.course_id}/asdfjkl", {}, 'rack.session' => {"permission_for_#{@course.course_id}" => 'edit'}
      last_response.should be_ok
      assert_error_page("Session information lost")

      post "/badges/award/#{@domain.id}/asdf/asdfjkl", {}, 'rack.session' => {'permission_for_asdf' => 'edit', 'user_id' => 'asdf'}
      last_response.should be_ok
      assert_error_page("This badge has not been configured yet")
      

      post "/badges/award/#{@domain.id}/#{@course.course_id}/asdfjkl", {}, 'rack.session' => {"permission_for_#{@course.course_id}" => 'edit', 'user_id' => 'asdf'}
      last_response.should be_ok
      assert_error_page("This badge has not been configured yet")
      
      @course.settings['min_percent'] = 10
      @course.save
      BadgeHelpers.stub!(:api_call).and_return([])

      post "/badges/award/#{@domain.id}/#{@course.course_id}/asdfjkl", {}, 'rack.session' => {"permission_for_#{@course.course_id}" => 'edit', 'user_id' => 'asdf'}
      last_response.should be_ok
      assert_error_page("That user is not a student in this course")

      user
      BadgeHelpers.stub!(:api_call).and_return([{'id' => @user.user_id.to_i, 'name' => 'bob', 'email' => 'bob@example.com'}])
      post "/badges/award/#{@domain.id}/#{@course.course_id}/#{@user.user_id}", {}, 'rack.session' => {"permission_for_#{@course.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@domain.id}/#{@course.course_id}/#{@user.user_id}"
    end
    
    it "should allow instructors to manually award the badge for their students" do
      course
      user
      @course.settings['min_percent'] = 10
      @course.save
      BadgeHelpers.stub!(:api_call).and_return([{'id' => @user.user_id.to_i, 'name' => 'bob', 'email' => 'bob@example.com'}])
      post "/badges/award/#{@domain.id}/#{@course.course_id}/#{@user.user_id}", {}, 'rack.session' => {"permission_for_#{@course.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_redirect
      last_response.location.should == "http://example.org/badges/check/#{@domain.id}/#{@course.course_id}/#{@user.user_id}"
    end
  end
end
