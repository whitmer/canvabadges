require File.dirname(__FILE__) + '/spec_helper'

describe 'Badging Models' do
  include Rack::Test::Methods
  
  def app
    Canvabadges
  end
  
  describe "UserConfig model" do
    it "should return 'host' from the domain model" do
      user
      @user.host.should == "bob.com"
    end
    
    it "should fail gracefully if no host specified" do
      @user = UserConfig.create
      @user.host.should == nil
    end
  end  
  
  describe "BadgeConfig model" do
    it "should generate nonce on save" do
      @bc = BadgeConfig.create
      @bc.nonce.should_not be_nil
    end
    
    describe "configuration options" do
      it "should check if actually configured" do
        badge_config
        @badge_placement_config.configured?.should be_false
        @badge_config.settings = {
          'badge_name' => "Cool Badge",
          'badge_description' => "Badge for cool people",
          'badge_url' => "http://example.com/badge"
        }
        @badge_placement_config.settings = {'min_percent' => 0}
        @badge_config.save
        @badge_config.configured?.should be_true
        @badge_placement_config.save
        @badge_placement_config.reload
        @badge_placement_config.configured?.should be_true
        
        BadgePlacementConfig.create.configured?.should be_false
      end
      
      it "check if modules are required" do
        badge_config
        @badge_placement_config.modules_required?.should be_false
        
        @badge_placement_config.settings['modules'] = {
          '1' => 'Module 1',
          '2' => 'Module 2',
        }.to_a
        @badge_placement_config.save
        @badge_placement_config.modules_required?.should be_true
      end
      
      it "should return list of required modules" do
        badge_config
        @badge_placement_config.required_modules.should == []
        
        @badge_placement_config.settings['modules'] = {
          '1' => 'Module 1',
          '2' => 'Module 2',
        }.to_a
        @badge_placement_config.save
        @badge_placement_config.required_modules.should == [['1', 'Module 1'], ['2', 'Module 2']]
      end
      
      it "should check if requirements are met" do
        badge_config
        @badge_placement_config.settings['min_percent'] = 10
        @badge_placement_config.settings['modules'] = {
          '1' => 'Module 1',
          '2' => 'Module 2',
        }.to_a
        @badge_placement_config.save
        @badge_placement_config.requirements_met?(9, [1, 2]).should be_false
        @badge_placement_config.requirements_met?(11, [1, 2]).should be_true
        @badge_placement_config.requirements_met?(11, [nil, 1, 2, 3]).should be_true
        @badge_placement_config.requirements_met?(11, [1]).should be_false
        @badge_placement_config.requirements_met?(11, [2]).should be_false
        @badge_placement_config.requirements_met?(11, []).should be_false
        @badge_placement_config.requirements_met?(11, [nil, "1", "2"]).should be_false
      end
    end
  end  
  
  describe "Badge model" do
    describe "OBI badge JSON" do
      it "should return valid OBI data for badge" do
        award_badge(badge_config, user)
        hash = @badge.open_badge_json("bob.com")
        sha = Digest::SHA256.hexdigest(@badge.email + @badge.salt)
        hash[:recipient].should == {
          :hashed => true,
          :identity => @badge.recipient,
          :salt => @badge.salt,
          :type => "email"
        }
        hash[:badge].should == "https://bob.com/api/v1/badges/summary/#{@badge_config.id}/#{@badge_config.nonce}.json"
        hash[:evidence].should == "https://bob.com/badges/criteria/#{@badge_config.id}/#{@badge_config.nonce}?user=#{@badge.nonce}"
        hash[:image].should == @badge_config.settings['badge_url']
      end
      
      it "should not fail if invalid badge data crops up somehow" do
        award_badge(badge_config, user)
        @badge.issued = nil
        @badge.badge_config = nil
        hash = @badge.open_badge_json("bob.com")
        hash.keys.should be_include(:recipient)
        hash.keys.should be_include(:issuedOn)
        hash.keys.should be_include(:badge)
      end
      
      it "should use the correct host and port" do
        award_badge(badge_config, user)
        hash = @badge.open_badge_json("alpha.net")
        hash[:badge].should == "https://alpha.net/api/v1/badges/summary/#{@badge_config.id}/#{@badge_config.nonce}.json"
        
        hash = @badge_config.as_json("alpha.org")
        hash[:issuer].should == "https://alpha.org/api/v1/organizations/default.json"
      end
    end
    
    it "should generate defaults on save" do
      @badge = Badge.create(:email => "asdf")
      @badge.nonce.should_not be_nil
      @badge.salt.should_not be_nil
    end
    
    it "should return valid user name" do
      user
      @user.name = "Bobbyo"
      @user.save
      award_badge(badge_config, @user)
      @badge.user_full_name = "Fred"
      @badge.user_name.should == "Bobbyo"
      
      @badge.user_id = nil
      @badge.user_name.should == "Fred"
    end
    
    it "should return valid badge_config nonce" do
      award_badge(badge_config, user)
      @badge.config_nonce.should == @badge_config.nonce
    end
    
    it "should clear nonce when config is removed" do
      award_badge(badge_config, user)
      @badge.config_nonce.should == @badge_config.nonce

      @badge.badge_config.destroy
      @badge.badge_config = nil
      @badge.badge_placement_config = nil
      @badge.config_nonce.should == nil
    end
    
    it "should allow generating badges" do
      badge_config
      user
      badge = Badge.generate_badge({'user_id' => @user.user_id, 'badge_placement_config_id' => @badge_placement_config.id}, @badge_placement_config, @user.name, "email@email.com")
      badge.user_id.should == @user.user_id
      badge.badge_config_id.should == @badge_config.id
      badge.placement_id.should == @badge_placement_config.placement_id
      badge.name.should == @badge_config.settings['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @badge_config.settings['badge_description']
      badge.badge_url.should == @badge_config.settings['badge_url']
      badge.issued.should be_nil
      badge.state.should == 'unissued'
    end
    
    it "should allow manually awarding new badges" do
      badge_config
      user
      badge = Badge.manually_award({'user_id' => @user.user_id, 'badge_placement_config_id' => @badge_placement_config.id}, @badge_placement_config, @user.name, "email@email.com")
      badge.user_id.should == @user.user_id
      badge.placement_id.should == @badge_placement_config.placement_id
      badge.name.should == @badge_config.settings['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @badge_config.settings['badge_description']
      badge.badge_url.should == @badge_config.settings['badge_url']
      badge.issued.should_not be_nil
      badge.state.should == 'awarded'
    end
    
    it "should allow manually awarding existing badges" do
      award_badge(badge_config, user)
      badge = Badge.manually_award({'user_id' => @user.user_id, 'badge_placement_config_id' => @badge_placement_config.id}, @badge_placement_config, @user.name, "email@email.com")
      badge.id.should == @badge.id
      badge.user_id.should == @user.user_id
      badge.placement_id.should == @badge_placement_config.placement_id
      badge.name.should == @badge_config.settings['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @badge_config.settings['badge_description']
      badge.badge_url.should == @badge_config.settings['badge_url']
      badge.issued.should_not be_nil
      badge.state.should == 'awarded'
    end
    
    it "should allow completing new badges" do
      badge_config
      user
      badge = Badge.complete({'user_id' => @user.user_id, 'badge_placement_config_id' => @badge_placement_config.id}, @badge_placement_config, @user.name, "email@email.com")
      badge.user_id.should == @user.user_id
      badge.placement_id.should == @badge_placement_config.placement_id
      badge.name.should == @badge_config.settings['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @badge_config.settings['badge_description']
      badge.badge_url.should == @badge_config.settings['badge_url']
      badge.issued.should_not be_nil
      badge.state.should == 'awarded'
    end
    
    it "should allow completing existing badges" do
      award_badge(badge_config, user)
      badge = Badge.complete({'user_id' => @user.user_id, 'badge_placement_config_id' => @badge_placement_config.id}, @badge_placement_config, @user.name, "email@email.com")
      badge.id.should == @badge.id
      badge.user_id.should == @user.user_id
      badge.placement_id.should == @badge_placement_config.placement_id
      badge.name.should == @badge_config.settings['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @badge_config.settings['badge_description']
      badge.badge_url.should == @badge_config.settings['badge_url']
      badge.issued.should_not be_nil
      badge.state.should == 'awarded'
    end
    
    it "should pend manual approval badges" do
      badge_config
      user
      @badge_placement_config.settings['manual_approval'] = true
      @badge_placement_config.save
      badge = Badge.complete({'user_id' => @user.user_id, 'badge_placement_config_id' => @badge_placement_config.id}, @badge_placement_config, @user.name, "email@email.com")
      badge.user_id.should == @user.user_id
      badge.placement_id.should == @badge_placement_config.placement_id
      badge.name.should == @badge_config.settings['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @badge_config.settings['badge_description']
      badge.badge_url.should == @badge_config.settings['badge_url']
      badge.state.should == 'pending'
      badge.issued.should be_nil
    end
    
    it "should include custom issuer information on badge awards" do
      badge_config
      user
      badge = Badge.complete({'user_id' => @user.user_id, 'badge_placement_config_id' => @badge_placement_config.id}, @badge_placement_config, @user.name, "email@email.com")
      json = badge.open_badge_json("example.com")
      json[:badge].should_not be_nil
      json[:badge].should == "https://example.com/api/v1/badges/summary/#{@badge_config.id}/#{@badge_config.nonce}.json"
      
      json = @badge_config.as_json("example.com")
      json[:issuer].should == "https://example.com/api/v1/organizations/default.json"
      
      Organization.new(:host => "example.com").as_json.should == {
        'name' => BadgeHelper.issuer['name'],
        'url' => BadgeHelper.issuer['url'],
        'description' => BadgeHelper.issuer['description'],
        'image' => "https://example.com/organizations/default.png",
        'email' => BadgeHelper.issuer['email'],
        'revocationList' => "#{BadgeHelper.protocol}://example.com/api/v1/organizations/default/revocations.json"
      }
      

      configured_school      
      @badge_config.organization = @school
      json = @badge_config.as_json("example.com")
      json[:issuer].should == "https://example.com/api/v1/organizations/#{@school.id}-my-school.json"
      @school.as_json.should == {
       "description" => "My School has been around a long time",
       "email" => "admin@myschool.edu",
       "image" => "http://myschool.edu/logo.png",
       "name" => "My School",
       "revocationList" => "https://badges.myschool.edu/api/v1/organizations/#{@school.id}/revocations.json",
       "url" => "http://myschool.edu"
      }
    end
  end  

end
