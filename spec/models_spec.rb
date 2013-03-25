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

    describe "root configuration" do
      it "should allow setting root config from ref code" do
        @bc = badge_config
        @bc2 = badge_config
        @bc2.set_root_from_reference_code(@bc.reference_code)
        @bc2.root_id.should == @bc.id
      end
      
      it "should not fail if root isn't found" do
        badge_config
        @badge_config.root_id.should == nil
        @badge_config.set_root_from_reference_code("")
        @badge_config.root_id.should == nil
        @badge_config.set_root_from_reference_code(nil)
        @badge_config.root_id.should == nil
        @badge_config.set_root_from_reference_code("bunk")
        @badge_config.root_id.should == nil
      end
      
      it "should pull settings from root config if set" do
        @bc1 = badge_config
        @bc2 = badge_config
        @bc1.settings = {
          'badge_name' => "Cooler Badge",
          'badge_description' => "Badge for cooler people",
          'badge_url' => "http://example.com/badge/cooler"
        }
        @bc1.save
        @bc2.set_root_from_reference_code(@bc1.reference_code)
        @bc2.root_settings.should == @bc1.settings
      end
      
      it "should return current config if no root config set" do
        badge_config
        @badge_config.root_settings.should == @badge_config.settings
      end
      
      it "should pull nonce from root config if set" do
        @bc1 = badge_config
        @bc2 = badge_config
        @bc2.set_root_from_reference_code(@bc1.reference_code)
        @bc2.root_nonce.should == @bc1.nonce
      end
      
      it "should return current nonce if no root config set" do
        badge_config
        @badge_config.root_nonce.should == @badge_config.nonce
      end
    end
    
    describe "configuration options" do
      it "should check if actually configured" do
        badge_config
        @badge_config.settings = {
          'badge_name' => "Cool Badge",
          'badge_description' => "Badge for cool people",
          'badge_url' => "http://example.com/badge",
          'min_percent' => 10
        }
        @badge_config.save
        @badge_config.configured?.should be_true
        
        BadgeConfig.create.configured?.should be_false
      end
      
      it "check if modules are required" do
        badge_config
        @badge_config.modules_required?.should be_false
        
        @badge_config.settings['modules'] = {
          '1' => 'Module 1',
          '2' => 'Module 2',
        }.to_a
        @badge_config.save
        @badge_config.modules_required?.should be_true
      end
      
      it "should return list of required modules" do
        badge_config
        @badge_config.required_modules.should == []
        
        @badge_config.settings['modules'] = {
          '1' => 'Module 1',
          '2' => 'Module 2',
        }.to_a
        @badge_config.save
        @badge_config.required_modules.should == [['1', 'Module 1'], ['2', 'Module 2']]
      end
      
      it "should check if requirements are met" do
        badge_config
        @badge_config.settings['min_percent'] = 10
        @badge_config.settings['modules'] = {
          '1' => 'Module 1',
          '2' => 'Module 2',
        }.to_a
        @badge_config.save
        @badge_config.requirements_met?(9, [1, 2]).should be_false
        @badge_config.requirements_met?(11, [1, 2]).should be_true
        @badge_config.requirements_met?(11, [nil, 1, 2, 3]).should be_true
        @badge_config.requirements_met?(11, [1]).should be_false
        @badge_config.requirements_met?(11, [2]).should be_false
        @badge_config.requirements_met?(11, []).should be_false
        @badge_config.requirements_met?(11, [nil, "1", "2"]).should be_false
      end
    end
  end  
  
  describe "Badge model" do
    describe "OBI badge JSON" do
      it "should return valid OBI data for badge" do
        award_badge(badge_config, user)
        hash = @badge.open_badge_json("bob.com")
        sha = Digest::SHA256.hexdigest(@badge.email + @badge.salt)
        hash[:recipient].should == "sha256$#{sha}"
        hash[:salt].should_not be_nil
        hash[:issued_on] = Time.now.strftime("%Y-%m-%d")
        hash[:badge].should_not be_nil
        hash[:badge][:version].should == '0.5.0'
        hash[:badge][:name].should == @badge.name
        hash[:badge][:image].should == "http://example.com/badge"
        hash[:badge][:description].should == "Badge for cool people"
        hash[:badge][:criteria].should == "https://bob.com/badges/criteria/#{@badge.config_nonce}"
        hash[:badge][:issuer].should_not be_nil
        hash[:badge][:issuer][:origin].should == "https://bob.com"
        hash[:badge][:issuer][:name].should == "Canvabadges"
        hash[:badge][:issuer][:org].should == "Instructure, Inc."
        hash[:badge][:issuer][:contact].should == "support@instructure.com"
      end
      
      it "should not fail if invalid badge data crops up somehow" do
        award_badge(badge_config, user)
        @badge.issued = nil
        @badge.badge_config = nil
        hash = @badge.open_badge_json("bob.com")
        hash.keys.should be_include(:recipient)
        hash.keys.should be_include(:salt)
        hash.keys.should be_include(:issued_on)
        hash.keys.should be_include(:badge)
        hash[:badge].keys.should be_include(:version)
        hash[:badge].keys.should be_include(:name)
        hash[:badge].keys.should be_include(:image)
        hash[:badge].keys.should be_include(:description)
        hash[:badge].keys.should be_include(:criteria)
        hash[:badge].keys.should be_include(:issuer)
        hash[:badge][:issuer].keys.should be_include(:origin)
        hash[:badge][:issuer].keys.should be_include(:name)
        hash[:badge][:issuer].keys.should be_include(:org)
        hash[:badge][:issuer].keys.should be_include(:contact)
      end
      
      it "should use the correct host and port" do
        award_badge(badge_config, user)
        hash = @badge.open_badge_json("alpha.net")
        hash[:badge][:criteria].should == "https://alpha.net/badges/criteria/#{@badge.config_nonce}"
        hash[:badge][:issuer][:origin].should == "https://alpha.net"
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
      @badge.config_nonce.should == nil
    end
    
    it "should allow generating badges" do
      badge_config
      user
      badge = Badge.generate_badge({'user_id' => @user.user_id, 'placement_id' => @badge_config.placement_id, 'domain_id' => @domain.id}, @badge_config, @user.name, "email@email.com")
      badge.user_id.should == @user.user_id
      badge.badge_config_id.should == @badge_config.id
      badge.placement_id.should == @badge_config.placement_id
      badge.name.should == @badge_config.settings['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @badge_config.settings['badge_description']
      badge.badge_url.should == @badge_config.settings['badge_url']
      badge.issued.should be_nil
      badge.state.should be_nil
    end
    
    it "should allow manually awarding new badges" do
      badge_config
      user
      badge = Badge.manually_award({'user_id' => @user.user_id, 'placement_id' => @badge_config.placement_id, 'domain_id' => @domain.id}, @badge_config, @user.name, "email@email.com")
      badge.user_id.should == @user.user_id
      badge.placement_id.should == @badge_config.placement_id
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
      badge = Badge.manually_award({'user_id' => @user.user_id, 'placement_id' => @badge_config.placement_id, 'domain_id' => @domain.id}, @badge_config, @user.name, "email@email.com")
      badge.id.should == @badge.id
      badge.user_id.should == @user.user_id
      badge.placement_id.should == @badge_config.placement_id
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
      badge = Badge.complete({'user_id' => @user.user_id, 'placement_id' => @badge_config.placement_id, 'domain_id' => @domain.id}, @badge_config, @user.name, "email@email.com")
      badge.user_id.should == @user.user_id
      badge.placement_id.should == @badge_config.placement_id
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
      badge = Badge.complete({'user_id' => @user.user_id, 'placement_id' => @badge_config.placement_id, 'domain_id' => @domain.id}, @badge_config, @user.name, "email@email.com")
      badge.id.should == @badge.id
      badge.user_id.should == @user.user_id
      badge.placement_id.should == @badge_config.placement_id
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
      @badge_config.settings['manual_approval'] = true
      @badge_config.save
      badge = Badge.complete({'user_id' => @user.user_id, 'placement_id' => @badge_config.placement_id, 'domain_id' => @domain.id}, @badge_config, @user.name, "email@email.com")
      badge.user_id.should == @user.user_id
      badge.placement_id.should == @badge_config.placement_id
      badge.name.should == @badge_config.settings['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @badge_config.settings['badge_description']
      badge.badge_url.should == @badge_config.settings['badge_url']
      badge.issued.should be_nil
      badge.state.should == 'pending'
    end
  end  

end
