RACK_ENV='test'
ENV['RACK_ENV']='test'
require 'rspec'
require 'rack/test'
require 'json'
require './canvabadges'

RSpec.configure do |config|
  config.before(:each) { 
    DataMapper.auto_migrate! 
    domain("bob.com", "Bob")
    @config = ExternalConfig.create(:config_type => 'canvas_oauth', :value => 'abc', :shared_secret => 'xyz')
  }
end

def prefix_org
  @org = Organization.create(:host => "example.org/_test", :settings => {'name' => 'Test With Prefix'})
end

def example_org
  @org ||= Organization.create(:host => "example.org", :settings => {'name' => 'Canvabadges', 'default' => true})
end

def configured_school
  @school = Organization.create(
    'host' => 'badges.myschool.edu',
    'settings' => {
      'name' => "My School",
      'url' => "http://myschool.edu",
      'description' => "My School has been around a long time",
      'image' => "http://myschool.edu/logo.png",
      'email' => "admin@myschool.edu"
    }
  )
  @school.as_json['name'].should == "My School"
  @school
end

def get_with_session(path, hash={}, args={})
  args['rack.session'] ||= {}
  session.keys.each do |k, v|
    args['rack.session'][k] = v unless args['rack.session'][k] == nil
  end
  get path, hash, args
end

def post_with_session(path, hash={}, args={})
  args['rack.session'] ||= {}
  session.keys.each do |k, v|
    args['rack.session'][k] = v unless args['rack.session'][k] == nil
  end
  post path, hash, args
end

def session
  last_request.env['rack.session']
end

def user
  id = Time.now.to_i.to_s + "_" + rand.round(8).to_s
  @user = UserConfig.create!(:user_id => id, :name => id, :domain_id => @domain.id) 
end

def badge_config(org=nil)
  id = Time.now.to_i.to_s + rand.round(8).to_s
  @badge_config = BadgeConfig.new(:domain_id => @domain.id, :external_config_id => @config.id)
  @badge_config.settings = {
    'badge_name' => "Cool Badge",
    'badge_description' => "Badge for cool people",
    'badge_url' => "http://example.com/badge/#{rand(10000)}"
  }
  @org = org if org
  @badge_config.organization_id = @org && @org.id
  @badge_config.save
  @badge_config.nonce.should_not be_nil
  @badge_config
  @badge_placement_config = BadgePlacementConfig.create(:placement_id => id, :domain_id => @domain.id, :course_id => '123', :external_config_id => @config.id, :badge_config_id => @badge_config.id, :settings => {})
  @badge_placement_config.badge_config.should == @badge_config
  @badge_placement_config
end

def course
  id = Time.now.to_i.to_s + rand.round(8).to_s
  @course = CourseConfig.new(:course_id => id, :domain_id => @domain.id)
  @course.settings = {
    'badge_name' => "Cool Badge",
    'badge_description' => "Badge for cool people",
    'badge_url' => "http://example.com/badge"
  }
  @course.save
  @course.nonce.should_not be_nil
  @course
end

def configured_badge(min_percent=nil)
  badge_config
  hash = @badge_config.settings
  hash['min_percent'] = min_percent || rand(1000) / 10.0
  @badge_placement_config.settings = hash
  @badge_placement_config.save
  @badge_config.should be_configured
  @badge_placement_config.reload
end

def module_configured_badge(min_percent=nil)
  badge_config
  hash = @badge_placement_config.settings
  hash['min_percent'] = min_percent || rand(1000) / 10.0
  hash['modules'] = [['1', 'Module 1', 0], ['2', 'Module 2', 0]]
  @badge_placement_config.settings = hash
  @badge_placement_config.save
  @badge_placement_config.should be_configured
  @badge_placement_config
end

def module_outcome_configured_badge(min_percent=nil)
  badge_config
  hash = @badge_placement_config.settings
  hash['min_percent'] = min_percent || rand(1000) / 10.0
  hash['modules'] = [['1', 'Module 1', 0], ['2', 'Module 2', 0]]
  hash['outcomes'] = [['1', 'Outcome 1', 0], ['2', 'Outcome 2', 0]]
  @badge_placement_config.settings = hash
  @badge_placement_config.save
  @badge_placement_config.should be_configured
  @badge_placement_config
end

def outcome_configured_badge(min_percent=nil)
  badge_config
  hash = @badge_placement_config.settings
  hash['min_percent'] = min_percent || rand(1000) / 10.0
  hash['outcomes'] = [['1', 'Outcome 1', 0], ['2', 'Outcome 2', 0]]
  @badge_placement_config.settings = hash
  @badge_placement_config.save
  @badge_placement_config.should be_configured
  @badge_placement_config
end

def credit_configured_badge(min_percent=nil)
  badge_config
  hash = @badge_placement_config.settings
  hash['min_percent'] = min_percent || rand(1000) / 10.0
  hash['modules'] = [['1', 'Module 1', 3], ['2', 'Module 2', 3]]
  hash['credit_based'] = true
  hash['required_credits'] = 5
  hash['credits_for_final_score'] = 3
  
  @badge_placement_config.settings = hash
  @badge_placement_config.save
  @badge_placement_config.should be_configured
  @badge_placement_config
end

def credit_outcome_configured_badge(min_percent=nil)
  badge_config
  hash = @badge_placement_config.settings
  hash['min_percent'] = min_percent || rand(1000) / 10.0
  hash['outcomes'] = [['1', 'Outcome 1', 3], ['2', 'Outcome 2', 3]]
  hash['credit_based'] = true
  hash['required_credits'] = 5
  hash['credits_for_final_score'] = 3
  
  @badge_placement_config.settings = hash
  @badge_placement_config.save
  @badge_placement_config.should be_configured
  @badge_placement_config
end

def old_school_configured_badge
  id = Time.now.to_i.to_s + rand.round(8).to_s
  @badge_config = BadgeConfig.new(:domain_id => @domain.id, :external_config_id => @config.id)
  @badge_config.settings = {
    'badge_name' => "Cool Badge",
    'badge_description' => "Badge for cool people",
    'badge_url' => "http://example.com/badge/#{rand(10000)}",
    'min_percent' => rand(1000) / 10.0,
    'modules' => [['1', 'Module 1', 3], ['2', 'Module 2', 3]],
    'credit_based' => true,
    'required_credits' => 5,
    'credits_for_final_score' => 3
  }
  @badge_config.placement_id = id
  @badge_config.course_id = '123'
  @badge_config.organization_id = @org && @org.id
  @badge_config.save
  @badge_config
end

def award_badge(badge_placement_config, user)
  params = {
    'user_id' => user.user_id,
    'placement_id' => badge_placement_config.placement_id,
    'domain_id' => badge_placement_config.domain_id
  }
  @badge = Badge.manually_award(params, badge_placement_config, user.name, "email@bob.com")  
  @badge.nonce.should_not be_nil
  @badge
end

def badge_json(badge, user)
  {
    :id => user.user_id,
    :name => user.name,
    :manual => badge.manual_approval,
    :public => badge.public,
    :image_url => badge.badge_url,
    :issued => badge.issued.strftime('%b %e, %Y'),
    :nonce => badge.nonce,
    :state => badge.state,
    :evidence_url => badge.evidence_url,
    :config_id => badge.badge_config_id,
    :placement_config_id => badge.badge_placement_config_id,
    :config_nonce => badge.config_nonce
  }
end

def fake_badge_json(badge_placement_config, user_id, user_name)
  {
    :id => user_id,
    :name => user_name,
    :manual => nil,
    :public => nil,
    :image_url => nil,
    :issued => nil,
    :nonce => nil,
    :state => 'unissued',
    :evidence_url => nil,
    :config_id => nil,
    :placement_config_id => nil,
    :config_nonce => badge_placement_config.nonce
  }
end

def assert_error_page(msg)
  last_response.body.should match(msg)
end

def domain(host, name)
  @domain = Domain.create!(:host => host, :name => name)
end