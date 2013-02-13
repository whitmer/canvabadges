require File.dirname(__FILE__) + '/spec_helper'

describe 'Badging Models' do
  include Rack::Test::Methods
  
  def app
    Sinatra::Application
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
  
  describe "CourseConfig model" do
    it "should generate nonce on save" do
      @course = CourseConfig.create
      @course.nonce.should_not be_nil
    end

    describe "root configuration" do
      it "should allow setting root config from ref code" do
        @course1 = course
        @course2 = course
        @course2.set_root_from_reference_code(@course1.reference_code)
        @course2.root_id.should == @course1.id
      end
      
      it "should not fail if root isn't found" do
        course
        @course.root_id.should == nil
        @course.set_root_from_reference_code("")
        @course.root_id.should == nil
        @course.set_root_from_reference_code(nil)
        @course.root_id.should == nil
        @course.set_root_from_reference_code("bunk")
        @course.root_id.should == nil
      end
      
      it "should pull settings from root config if set" do
        @course1 = course
        @course2 = course
        @course1.settings = {
          :badge_name => "Cooler Badge",
          :badge_description => "Badge for cooler people",
          :badge_url => "http://example.com/badge/cooler"
        }
        @course1.save
        @course2.set_root_from_reference_code(@course1.reference_code)
        @course2.root_settings.should == @course1.settings
      end
      
      it "should return current config if no root config set" do
        course
        @course.root_settings.should == @course.settings
      end
      
      it "should pull nonce from root config if set" do
        @course1 = course
        @course2 = course
        @course2.set_root_from_reference_code(@course1.reference_code)
        @course2.root_nonce.should == @course1.nonce
      end
      
      it "should return current nonce if no root config set" do
        course
        @course.root_nonce.should == @course.nonce
      end
    end
    
    describe "configuration options" do
      it "should check if actually configured" do
        course
        @course.settings = {
          :badge_name => "Cool Badge",
          :badge_description => "Badge for cool people",
          :badge_url => "http://example.com/badge",
          :min_percent => 10
        }.to_json
        @course.save
        @course.configured?.should be_true
        
        CourseConfig.create.configured?.should be_false
      end
      
      it "check if modules are required" do
        course
        course.modules_required?.should be_false
        
        @course.settings_hash['modules'] = {
          '1' => 'Module 1',
          '2' => 'Module 2',
        }.to_a
        @course.settings = @course.settings_hash.to_json
        @course.save
        @course.modules_required?.should be_true
      end
      
      it "should return list of required modules" do
        course
        course.required_modules.should == []
        
        @course.settings_hash['modules'] = {
          '1' => 'Module 1',
          '2' => 'Module 2',
        }.to_a
        @course.settings = @course.settings_hash.to_json
        @course.save
        @course.required_modules.should == [['1', 'Module 1'], ['2', 'Module 2']]
      end
      
      it "should check if requirements are met" do
        course
        @course.settings_hash['min_percent'] = 10
        @course.settings_hash['modules'] = {
          '1' => 'Module 1',
          '2' => 'Module 2',
        }.to_a
        @course.settings = @course.settings_hash.to_json
        @course.save
        @course.requirements_met?(9, [1, 2]).should be_false
        @course.requirements_met?(11, [1, 2]).should be_true
        @course.requirements_met?(11, [nil, 1, 2, 3]).should be_true
        @course.requirements_met?(11, [1]).should be_false
        @course.requirements_met?(11, [2]).should be_false
        @course.requirements_met?(11, []).should be_false
        @course.requirements_met?(11, [nil, "1", "2"]).should be_false
      end
    end
  end  
  
  describe "Badge model" do
    describe "OBI badge JSON" do
      it "should return valid OBI data for badge" do
        award_badge(course, user)
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
        hash[:badge][:criteria].should == "https://bob.com/badges/criteria/#{@badge.course_nonce}"
        hash[:badge][:issuer].should_not be_nil
        hash[:badge][:issuer][:origin].should == "https://bob.com"
        hash[:badge][:issuer][:name].should == "Canvabadges"
        hash[:badge][:issuer][:org].should == "Instructure, Inc."
        hash[:badge][:issuer][:contact].should == "support@instructure.com"
      end
      
      it "should not fail if invalid badge data crops up somehow" do
        award_badge(course, user)
        @badge.issued = nil
        @badge.course_config = nil
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
        award_badge(course, user)
        hash = @badge.open_badge_json("alpha.net")
        hash[:badge][:criteria].should == "https://alpha.net/badges/criteria/#{@badge.course_nonce}"
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
      award_badge(course, @user)
      @badge.user_full_name = "Fred"
      @badge.user_name.should == "Bobbyo"
      
      @badge.user_id = nil
      @badge.user_name.should == "Fred"
    end
    
    it "should return valid course nonce" do
      award_badge(course, user)
      @badge.course_nonce.should == @course.nonce
      
      @badge.course_config = nil
      @badge.course_id = nil
      @badge.course_nonce.should == nil
    end
    
    it "should allow generating badges" do
      course
      user
      badge = Badge.generate_badge({'user_id' => @user.user_id, 'course_id' => @course.course_id, 'domain_id' => @domain.id}, @course, @user.name, "email@email.com")
      badge.user_id.should == @user.user_id
      badge.course_id.should == @course.course_id
      badge.name.should == @course.settings_hash['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @course.settings_hash['badge_description']
      badge.badge_url.should == @course.settings_hash['badge_url']
      badge.issued.should be_nil
      badge.state.should be_nil
    end
    
    it "should allow manually awarding new badges" do
      course
      user
      badge = Badge.manually_award({'user_id' => @user.user_id, 'course_id' => @course.course_id, 'domain_id' => @domain.id}, @course, @user.name, "email@email.com")
      badge.user_id.should == @user.user_id
      badge.course_id.should == @course.course_id
      badge.name.should == @course.settings_hash['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @course.settings_hash['badge_description']
      badge.badge_url.should == @course.settings_hash['badge_url']
      badge.issued.should_not be_nil
      badge.state.should == 'awarded'
    end
    
    it "should allow manually awarding existing badges" do
      award_badge(course, user)
      badge = Badge.manually_award({'user_id' => @user.user_id, 'course_id' => @course.course_id, 'domain_id' => @domain.id}, @course, @user.name, "email@email.com")
      badge.id.should == @badge.id
      badge.user_id.should == @user.user_id
      badge.course_id.should == @course.course_id
      badge.name.should == @course.settings_hash['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @course.settings_hash['badge_description']
      badge.badge_url.should == @course.settings_hash['badge_url']
      badge.issued.should_not be_nil
      badge.state.should == 'awarded'
    end
    
    it "should allow completing new badges" do
      course
      user
      badge = Badge.complete({'user_id' => @user.user_id, 'course_id' => @course.course_id, 'domain_id' => @domain.id}, @course, @user.name, "email@email.com")
      badge.user_id.should == @user.user_id
      badge.course_id.should == @course.course_id
      badge.name.should == @course.settings_hash['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @course.settings_hash['badge_description']
      badge.badge_url.should == @course.settings_hash['badge_url']
      badge.issued.should_not be_nil
      badge.state.should == 'awarded'
    end
    
    it "should allow completing existing badges" do
      award_badge(course, user)
      badge = Badge.complete({'user_id' => @user.user_id, 'course_id' => @course.course_id, 'domain_id' => @domain.id}, @course, @user.name, "email@email.com")
      badge.id.should == @badge.id
      badge.user_id.should == @user.user_id
      badge.course_id.should == @course.course_id
      badge.name.should == @course.settings_hash['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @course.settings_hash['badge_description']
      badge.badge_url.should == @course.settings_hash['badge_url']
      badge.issued.should_not be_nil
      badge.state.should == 'awarded'
    end
    
    it "should pend manual approval badges" do
      course
      user
      @course.settings_hash['manual_approval'] = true
      @course.settings = @course.settings_hash.to_json
      @course.save
      badge = Badge.complete({'user_id' => @user.user_id, 'course_id' => @course.course_id, 'domain_id' => @domain.id}, @course, @user.name, "email@email.com")
      badge.user_id.should == @user.user_id
      badge.course_id.should == @course.course_id
      badge.name.should == @course.settings_hash['badge_name']
      badge.email.should == "email@email.com"
      badge.user_full_name.should == @user.name
      badge.description.should == @course.settings_hash['badge_description']
      badge.badge_url.should == @course.settings_hash['badge_url']
      badge.issued.should be_nil
      badge.state.should == 'pending'
    end
  end  

end
