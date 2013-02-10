require File.dirname(__FILE__) + '/spec_helper'

describe 'Badges API' do
  include Rack::Test::Methods
  
  def app
    Sinatra::Application
  end
  
  describe "public badges for user" do
    it "should return nothing if no user" do
      get "/api/v1/badges/public/1/bob.com.json"
      last_response.should be_ok
      last_response.body.should == {:objects => []}.to_json
    end
    it "should return nothing if user with no badges" do
      user
      get "/api/v1/badges/public/#{@user.user_id}/bob.com.json"
      last_response.should be_ok
      last_response.body.should == {:objects => []}.to_json
    end
    it "should return nothing if user with badges but none are public" do
      award_badge(course, user)
      get "/api/v1/badges/public/#{@user.user_id}/bob.com.json"
      last_response.should be_ok
      last_response.body.should == {:objects => []}.to_json
    end
    it "should return badges that are public for the user" do
      award_badge(course, user)
      @badge.public = true
      @badge.save!
      get "/api/v1/badges/public/#{@user.user_id}/bob.com.json"
      last_response.should be_ok
      last_response.body.should == {:objects => [badge_json(@badge, @user)]}.to_json
    end
    it "should only return badges that are public for the user" do
      award_badge(course, user)
      @course1 = @course
      @badge1 = @badge
      award_badge(course, @user)
      @badge.public = true
      @badge.save!
      get "/api/v1/badges/public/#{@user.user_id}/bob.com.json"
      last_response.should be_ok
      last_response.body.should == {:objects => [badge_json(@badge, @user)]}.to_json
    end
  end  
  
  describe "awarded badges for course" do
    it "should require instructor/admin authorization" do
      course
      get "/api/v1/badges/awarded/#{@course.domain_id}/#{@course.course_id}.json"
      last_response.should be_ok
      last_response.body.should == {"error" => "Invalid permissions"}.to_json      
    end
    
    it "should return nothing if no course" do
      user
      get "/api/v1/badges/awarded/#{@domain.id}/123.json", {}, 'rack.session' => {"permission_for_123" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should == {:meta => {:next => nil}, :objects => []}.to_json      
    end
    
    it "should return awarded badges if there are any" do
      award_badge(course, user)
      get "/api/v1/badges/awarded/#{@course.domain_id}/#{@course.course_id}.json", {}, 'rack.session' => {"permission_for_#{@course.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should == {:meta => {:next => nil}, :objects => [badge_json(@badge, @user)]}.to_json      
    end
    it "should return paginated results" do
      award_badge(course, user)
      @admin = @user
      55.times do
        award_badge(@course, user)
      end
      get "/api/v1/badges/awarded/#{@course.domain_id}/#{@course.course_id}.json", {}, 'rack.session' => {"permission_for_#{@course.course_id}" => 'edit', 'user_id' => @admin.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['objects'].length.should == 50
      json['meta']['next'].should == "/api/v1/badges/awarded/#{@course.domain_id}/#{@course.course_id}.json?page=2"
      
      get json['meta']['next'], {}, 'rack.session' => {"permission_for_#{@course.course_id}" => 'edit', 'user_id' => @admin.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['meta']['next'].should == nil
      json['objects'].length.should == 6
    end
  end
  
  describe "active students for course" do
    it "should require instructor/admin authorization" do
      course
      get "/api/v1/badges/current/#{@course.domain_id}/#{@course.course_id}.json"
      last_response.should be_ok
      last_response.body.should == {"error" => "Invalid permissions"}.to_json      
    end
    
    it "should return nothing if no course" do
      user
      BadgeHelpers.stub!(:api_call).and_return([])
      get "/api/v1/badges/current/#{@domain.id}/123.json", {}, 'rack.session' => {"permission_for_123" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should == {:meta => {:next => nil}, :objects => []}.to_json      
    end
    
    it "should return active students if there are any" do
      course
      user
      s1 = fake_badge_json(@course, '123', 'bob')
      s2 = fake_badge_json(@course, '456', 'fred')
      BadgeHelpers.stub!(:api_call).and_return([{'id' => s1[:id], 'name' => s1[:name]}, {'id' => s2[:id], 'name' => s2[:name]}])
      get "/api/v1/badges/current/#{@domain.id}/#{@course.course_id}.json", {}, 'rack.session' => {"permission_for_#{@course.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should == {:meta => {:next => nil}, :objects => [s1, s2]}.to_json      
    end
    
    it "should return paginated results" do
      course
      user
      s1 = fake_badge_json(@course, '123', 'bob')
      s2 = fake_badge_json(@course, '456', 'fred')
      json = [{'id' => s1[:id], 'name' => s1[:name]}, {'id' => s2[:id], 'name' => s2[:name]}]
      json.instance_variable_set('@has_more', true)
      
      BadgeHelpers.stub!(:api_call).and_return(json)
      get "/api/v1/badges/current/#{@domain.id}/#{@course.course_id}.json", {}, 'rack.session' => {"permission_for_#{@course.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should == {:meta => {:next => "/api/v1/badges/current/#{@domain.id}/#{@course.course_id}.json?page=2"}, :objects => [s1, s2]}.to_json      
    end
  end
  
  describe "open badges data" do
    # HEAD and GET
    it "should respond to HEAD request" do
      award_badge(course, user)
      head "/api/v1/badges/data/#{@course.course_id}/#{@user.user_id}/#{@badge.nonce}.json"
      last_response.should be_ok      
    end
    
    it "should return nothing if invalid parameters" do
      award_badge(course, user)
      get "/api/v1/badges/data/#{@course.course_id}x/#{@user.user_id}/#{@badge.nonce}.json"
      last_response.should be_ok 
      last_response.body.should == {:error => "Not found"}.to_json

      get "/api/v1/badges/data/#{@course.course_id}/#{@user.user_id}x/#{@badge.nonce}.json"
      last_response.should be_ok 
      last_response.body.should == {:error => "Not found"}.to_json

      get "/api/v1/badges/data/#{@course.course_id}/#{@user.user_id}/#{@badge.nonce}x.json"
      last_response.should be_ok 
      last_response.body.should == {:error => "Not found"}.to_json
    end
    
    it "should return valid OBI badge data" do
      award_badge(course, user)
      get "/api/v1/badges/data/#{@course.course_id}/#{@user.user_id}/#{@badge.nonce}.json"
      last_response.should be_ok 
      last_response.body.should == @badge.open_badge_json("example.org").to_json
      json = JSON.parse(last_response.body)
      json['recipient'].should_not be_nil
      json['salt'].should_not be_nil
      json['issued_on'].should_not be_nil
      json['badge'].should_not be_nil
      json['badge']['version'].should_not be_nil      
      json['badge']['name'].should_not be_nil      
      json['badge']['image'].should_not be_nil      
      json['badge']['description'].should_not be_nil      
      json['badge']['criteria'].should_not be_nil      
      json['badge']['issuer'].should_not be_nil      
      json['badge']['issuer']['origin'].should_not be_nil      
      json['badge']['issuer']['name'].should_not be_nil      
      json['badge']['issuer']['org'].should_not be_nil      
      json['badge']['issuer']['contact'].should_not be_nil      
    end
  end
end
