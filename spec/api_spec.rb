require File.dirname(__FILE__) + '/spec_helper'

describe 'Badges API' do
  include Rack::Test::Methods
  
  def app
    Canvabadges
  end
  
  describe "public badges for user" do
    it "should return nothing if no user" do
      example_org
      get "/api/v1/badges/public/1/bob.com.json"
      last_response.should be_ok
      last_response.body.should == {:objects => []}.to_json
    end
    it "should return nothing if user with no badges" do
      example_org
      user
      get "/api/v1/badges/public/#{@user.user_id}/bob.com.json"
      last_response.should be_ok
      last_response.body.should == {:objects => []}.to_json
    end
    it "should return nothing if user with badges but none are public" do
      example_org
      award_badge(badge_config, user)
      get "/api/v1/badges/public/#{@user.user_id}/bob.com.json"
      last_response.should be_ok
      last_response.body.should == {:objects => []}.to_json
    end
    it "should return badges that are public for the user" do
      example_org
      award_badge(badge_config, user)
      @badge.public = true
      @badge.save!
      get "/api/v1/badges/public/#{@user.user_id}/bob.com.json"
      last_response.should be_ok
      last_response.body.should == {:objects => [badge_json(@badge, @user)]}.to_json
    end
    
    it "should support prefixed organizations" do
      prefix_org
      award_badge(badge_config, user)
      @badge.public = true
      @badge.save!
      get "/_test/api/v1/badges/public/#{@user.user_id}/bob.com.json"
      last_response.should be_ok
      last_response.body.should == {:objects => [badge_json(@badge, @user)]}.to_json
    end
    
    it "should only return badges that are public for the user" do
      example_org
      award_badge(badge_config, user)
      @bc1 = @badge_config
      @badge1 = @badge
      award_badge(badge_config, @user)
      @badge.public = true
      @badge.save!
      get "/api/v1/badges/public/#{@user.user_id}/bob.com.json"
      last_response.should be_ok
      last_response.body.should == {:objects => [badge_json(@badge, @user)]}.to_json
    end
    it "should not return badges that aren't in the 'awarded' state" do
      example_org
      award_badge(badge_config, user)
      @badge.public = true
      @badge.save!
      @good_badge = @badge
      
      award_badge(badge_config, @user)
      @badge.public = true
      @badge.state = 'revoked'
      @badge.save!
      get "/api/v1/badges/public/#{@user.user_id}/bob.com.json"
      last_response.should be_ok
      last_response.body.should == {:objects => [badge_json(@good_badge, @user)]}.to_json
    end
  end  
  
  describe "awarded badges for course" do
    it "should require instructor/admin authorization" do
      badge_config
      get "/api/v1/badges/awarded/#{@badge_config.id}.json"
      last_response.should_not be_ok
      last_response.body.should == {"error" => true, "message" => "Session information lost"}.to_json      
    end
    
    it "should return nothing if no course" do
      user
      get "/api/v1/badges/awarded/123.json", {}, 'rack.session' => {"permission_for_123" => 'edit', 'user_id' => @user.user_id}
      last_response.should_not be_ok
      last_response.body.should == {"error" => true, "message" => "Configuration not found"}.to_json
    end
    
    it "should return awarded badges if there are any" do
      award_badge(badge_config, user)
      get "/api/v1/badges/awarded/#{@badge_placement_config.id}.json", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should == {:meta => {:next => nil}, :objects => [badge_json(@badge, @user)]}.to_json      
    end
    
    it "should support prefixed orgs" do
      prefix_org
      award_badge(badge_config, user)
      get "/_test/api/v1/badges/awarded/#{@badge_placement_config.id}.json", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should == {:meta => {:next => nil}, :objects => [badge_json(@badge, @user)]}.to_json      
    end
    
    it "should not return pending or revoked badges" do
      award_badge(badge_config, user)
      @badge.state = 'revoked'
      @badge.save!
      get "/api/v1/badges/awarded/#{@badge_placement_config.id}.json", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should == {:meta => {:next => nil}, :objects => []}.to_json      
    end
    it "should return paginated results" do
      CanvasAPI.should_not_receive(:api_call)
      award_badge(badge_config, user)
      @admin = @user
      55.times do
        award_badge(@badge_placement_config, user)
      end
      get "/api/v1/badges/awarded/#{@badge_placement_config.id}.json", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => @admin.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['objects'].length.should == 50
      json['meta']['next'].should == "/api/v1/badges/awarded/#{@badge_placement_config.id}.json?page=2"
      
      get json['meta']['next'], {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => @admin.user_id}
      last_response.should be_ok
      json = JSON.parse(last_response.body)
      json['meta']['next'].should == nil
      json['objects'].length.should == 6
    end
  end
  
  describe "active students for course" do
    it "should require instructor/admin authorization" do
      badge_config
      get "/api/v1/badges/current/#{@badge_placement_config.id}.json"
      last_response.should_not be_ok
      last_response.body.should == {"error" => true, "message" => "Session information lost"}.to_json      
    end
    
    it "should return nothing if no course" do
      user
      get "/api/v1/badges/current/123.json", {}, 'rack.session' => {"permission_for_123" => 'edit', 'user_id' => @user.user_id}
      last_response.should_not be_ok
      last_response.body.should == {"error" => true, "message" => "Configuration not found"}.to_json      
    end
    
    it "should return active students if there are any" do
      badge_config
      user
      s1 = fake_badge_json(@badge_placement_config, '123', 'bob')
      s2 = fake_badge_json(@badge_placement_config, '456', 'fred')
      arr = [{'id' => s1[:id], 'name' => s1[:name]}, {'id' => s2[:id], 'name' => s2[:name]}]
      arr.stub(:more?).and_return(false)
      Canvabadges.any_instance.should_receive(:api_call).and_return(arr)
      get "/api/v1/badges/current/#{@badge_placement_config.id}.json", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should == {:meta => {:next => nil}, :objects => [s1, s2]}.to_json      
    end
    
    it "should return paginated results" do
      badge_config
      user
      s1 = fake_badge_json(@badge_placement_config, '123', 'bob')
      s2 = fake_badge_json(@badge_placement_config, '456', 'fred')
      json = [{'id' => s1[:id], 'name' => s1[:name]}, {'id' => s2[:id], 'name' => s2[:name]}]
      json.stub(:more?).and_return(true)
      
      Canvabadges.any_instance.should_receive(:api_call).and_return(json)
      get "/api/v1/badges/current/#{@badge_placement_config.id}.json", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should == {:meta => {:next => "/api/v1/badges/current/#{@badge_placement_config.id}.json?page=2"}, :objects => [s1, s2]}.to_json      
    end
    
    it "should support prefixed orgs" do
      prefix_org
      badge_config
      user
      s1 = fake_badge_json(@badge_placement_config, '123', 'bob')
      s2 = fake_badge_json(@badge_placement_config, '456', 'fred')
      json = [{'id' => s1[:id], 'name' => s1[:name]}, {'id' => s2[:id], 'name' => s2[:name]}]
      json.stub(:more?).and_return(true)
      
      Canvabadges.any_instance.should_receive(:api_call).and_return(json)
      get "/_test/api/v1/badges/current/#{@badge_placement_config.id}.json", {}, 'rack.session' => {"permission_for_#{@badge_placement_config.course_id}" => 'edit', 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should == {:meta => {:next => "/_test/api/v1/badges/current/#{@badge_placement_config.id}.json?page=2"}, :objects => [s1, s2]}.to_json      
    end
  end
  
  describe "open badges data" do
    it "should return nothing if invalid parameters" do
      example_org
      award_badge(badge_config, user)
      get "/api/v1/badges/data/#{@badge_config.id}x/#{@user.user_id}/#{@badge.nonce}.json"
      last_response.should_not be_ok 
      last_response.body.should == {:error => "Not found"}.to_json

      get "/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}x/#{@badge.nonce}.json"
      last_response.should_not be_ok 
      last_response.body.should == {:error => "Not found"}.to_json

      get "/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}x.json"
      last_response.should_not be_ok 
      last_response.body.should == {:error => "Not found"}.to_json
    end
    
    # HEAD and GET
    it "should respond to HEAD request" do
      example_org
      award_badge(badge_config, user)
      get "/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json"
      last_response.should be_ok      
    end
    
    it "should return valid OBI BadgeAssertion data" do
      example_org
      award_badge(badge_config, user)
      get "/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json"
      last_response.should be_ok 
      last_response.body.should == @badge.open_badge_json("example.org").to_json
      json = JSON.parse(last_response.body)
      json['recipient'].should_not be_nil
      json['recipient']['salt'].should_not be_nil
      json['verify'].should == {
        "type"=>"hosted", 
        "url"=>"https://example.org/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json"
      }
      json['issuedOn'].should_not be_nil
      json['badge'].should == "https://example.org/api/v1/badges/summary/#{@badge_config.id}/#{@badge_config.nonce}.json"
    end
    
    it "should use legacy domains when migrating a domain" do
      example_org
      @org.old_host = @org.host
      @org.host = "new." + @org.host
      @org.save
      new_domain = @org.host
      old_domain = @org.old_host

      award_badge(badge_config(@org), user)
      get "/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json", {}, 'HTTP_HOST' => old_domain
      last_response.should be_ok 
      last_response.body.should == @badge.open_badge_json("example.org").to_json
      json = JSON.parse(last_response.body)
      json['recipient'].should_not be_nil
      json['recipient']['salt'].should_not be_nil
      json['verify'].should == {
        "type"=>"hosted", 
        "url"=>"https://example.org/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json"
      }
      json['issuedOn'].should_not be_nil
      json['badge'].should == "https://example.org/api/v1/badges/summary/#{@badge_config.id}/#{@badge_config.nonce}.json"

      get "/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json", {}, 'HTTP_HOST' => new_domain
      last_response.should be_ok 
      last_response.body.should == @badge.open_badge_json("new.example.org").to_json
      json = JSON.parse(last_response.body)
      json['recipient'].should_not be_nil
      json['recipient']['salt'].should_not be_nil
      json['verify'].should == {
        "type"=>"hosted", 
        "url"=>"https://new.example.org/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json"
      }
      json['issuedOn'].should_not be_nil
      json['badge'].should == "https://new.example.org/api/v1/badges/summary/#{@badge_config.id}/#{@badge_config.nonce}.json"
    end
    
    it "should really be ok with domain migrations" do
      example_org
      @org.host = "www.canvabadges.org"
      @org.save

      award_badge(badge_config(@org), user)
      @org.host = "www.canvabadges.org"
      @org.old_host = "canvabadges.herokuapp.com"
      @org.save

      get "/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json", {}, 'HTTP_HOST' => @org.old_host
      last_response.should be_ok 
      last_response.body.should == @badge.open_badge_json("canvabadges.herokuapp.com").to_json
      json = JSON.parse(last_response.body)
      json['recipient'].should_not be_nil
      json['recipient']['salt'].should_not be_nil
      json['verify'].should == {
        "type"=>"hosted", 
        "url"=>"https://canvabadges.herokuapp.com/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json"
      }
      json['issuedOn'].should_not be_nil
      json['badge'].should == "https://canvabadges.herokuapp.com/api/v1/badges/summary/#{@badge_config.id}/#{@badge_config.nonce}.json"

      get "/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json", {}, 'HTTP_HOST' => @org.host
      last_response.should be_ok 
      last_response.body.should == @badge.open_badge_json("www.canvabadges.org").to_json
      json = JSON.parse(last_response.body)
      json['recipient'].should_not be_nil
      json['recipient']['salt'].should_not be_nil
      json['verify'].should == {
        "type"=>"hosted", 
        "url"=>"https://www.canvabadges.org/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json"
      }
      json['issuedOn'].should_not be_nil
      json['badge'].should == "https://www.canvabadges.org/api/v1/badges/summary/#{@badge_config.id}/#{@badge_config.nonce}.json"
    end
    
    it "should support prefixed orgs" do
      prefix_org
      award_badge(badge_config, user)
      get "/_test/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json"
      last_response.should be_ok 
      last_response.body.should == @badge.open_badge_json("example.org/_test").to_json
      json = JSON.parse(last_response.body)
      json['recipient'].should_not be_nil
      json['recipient']['salt'].should_not be_nil
      json['verify'].should == {
        "type"=>"hosted", 
        "url"=>"https://example.org/_test/api/v1/badges/data/#{@badge_config.id}/#{@user.user_id}/#{@badge.nonce}.json"
      }
      json['issuedOn'].should_not be_nil
      json['badge'].should == "https://example.org/_test/api/v1/badges/summary/#{@badge_config.id}/#{@badge_config.nonce}.json"
    end
    
    it "should return valid OBI BadgeClass data" do
      example_org
      award_badge(badge_config, user)
      get "/api/v1/badges/summary/#{@badge_config.id}/#{@badge_config.nonce}.json"
      last_response.should be_ok 
      last_response.body.should == @badge_config.as_json("example.org").to_json
      json = JSON.parse(last_response.body)
      json['name'].should_not be_nil
      json['description'].should_not be_nil
      json['image'].should_not be_nil
      json['criteria'].should_not be_nil
      json['issuer'].should_not be_nil
      
      json['name'].should == "Cool Badge"
      json['description'].should == "Badge for cool people"
      json['image'].should == @badge_config.settings['badge_url']
      json['criteria'].should == "https://example.org/badges/criteria/#{@badge_config.id}/#{@badge_config.nonce}"
      json['issuer'].should == "https://example.org/api/v1/organizations/#{@org.org_id}.json"
      json['alignment'].should == []
      json['tags'].should == []
    end
    
    it "should not find the badge information if requested from the wrong domain" do
      example_org
      configured_school
      award_badge(badge_config(@school), user)
      get "/api/v1/badges/summary/#{@badge_config.id}/#{@badge_config.nonce}.json"
      last_response.should_not be_ok 
      last_response.body.should == {:error => "not found"}.to_json
    end

    it "should return valid OBI IssuerOrganization data" do
      example_org
      get "/api/v1/organizations/default.json"
      last_response.body.should == Organization.new(:host => "example.org").to_json
      last_response.should be_ok 

      get "/api/v1/organizations/1234.json"
      last_response.should_not be_ok 
      last_response.body.should == {:error => "not found"}.to_json

      configured_school      
      get "/api/v1/organizations/#{@school.id}.json"
      last_response.should be_ok 
      last_response.body.should == @school.as_json.to_json
      json = JSON.parse(last_response.body)
      json['name'].should_not be_nil
      json['url'].should_not be_nil
      json['description'].should_not be_nil
      json['image'].should_not be_nil
      json['email'].should_not be_nil
      json['name'].should == @school.settings['name']
      json['url'].should == @school.settings['url']
      json['description'].should == @school.settings['description']
      json['image'].should == @school.settings['image']
      json['email'].should == @school.settings['email']
      json['revocationList'].should == "https://badges.myschool.edu/api/v1/organizations/#{@school.id}/revocations.json"
    end
    
    it "should not find the badge information if requested from the wrong domain" do
      example_org
      configured_school
      award_badge(badge_config(@school), user)
      get "/api/v1/badges/summary/#{@badge_config.id}/#{@badge_config.nonce}.json"
      last_response.should_not be_ok 
      last_response.body.should == {:error => "not found"}.to_json
    end
  end
end
