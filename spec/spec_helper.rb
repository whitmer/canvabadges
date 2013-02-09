RACK_ENV='test'
require 'rspec'
require 'rack/test'
require 'json'
require './canvabadges'

set :environment, :test

RSpec.configure do |config|
  config.before(:each) { 
    DataMapper.auto_migrate! 
    domain("bob.com", "Bob")
  }
end

def user
  id = Time.now.to_i.to_s + "_" + rand.round(8).to_s
  @user = UserConfig.create!(:user_id => id, :name => id, :domain_id => @domain.id) 
end

def course
  id = Time.now.to_i.to_s + rand.round(8).to_s
  @course = CourseConfig.new(:course_id => id, :domain_id => @domain.id)
  @course.settings = {
    :badge_name => "Cool Badge",
    :badge_description => "Badge for cool people",
    :badge_url => "http://example.com/badge"
  }.to_json
  @course.save!
  @course
end

def add_user(user, course)
end

def award_badge(course, user)
  params = {
    'user_id' => user.user_id,
    'course_id' => course.course_id,
    'domain_id' => course.domain_id
  }
  @badge = Badge.manually_award(params, course, user.name, "email@bob.com")  
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
    :course_nonce => badge.course_nonce
  }
end

def fake_badge_json(course, user_id, user_name)
  {
    :id => user_id,
    :name => user_name,
    :manual => nil,
    :public => nil,
    :image_url => nil,
    :issued => nil,
    :nonce => nil,
    :state => 'unissued',
    :course_nonce => course.nonce
  }
end

def domain(host, name)
  @domain = Domain.create!(:host => host, :name => name)
end