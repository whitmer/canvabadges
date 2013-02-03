require 'dm-core'
require 'dm-migrations'
require 'sinatra/base'

class Domain
  include DataMapper::Resource
  property :id, Serial
  property :host, String
  property :name, String
end

class ExternalConfig
  include DataMapper::Resource
  property :id, Serial
  property :config_type, String
  property :value, String
  property :shared_secret, String, :length => 256
end

class UserConfig
  include DataMapper::Resource
  property :id, Serial
  property :user_id, String
  property :access_token, String, :length => 256
  property :domain_id, Integer
  property :name, String, :length => 256
  property :global_user_id, String, :length => 256
  belongs_to :domain
  
  def host
    self.domain.host
  end
end

class CourseConfig
  include DataMapper::Resource
  property :id, Serial
  property :course_id, String
  property :nonce, String
  property :domain_id, Integer
  property :settings, Text
  property :root_id, Integer
  property :reference_code, String
  
  before :save, :generate_nonce
  
  def root_settings
    conf = self
    if self.root_id
      conf = CourseConfig.first(:id => self.root_id) || self
    end
    conf.settings
  end
  
  def root_nonce
    conf = self
    if self.root_id
      conf = CourseConfig.first(:id => self.root_id) || self
    end
    conf.nonce
  end
  
  def generate_nonce
    self.nonce ||= Digest::MD5.hexdigest(Time.now.to_i.to_s + rand.to_s)
    self.reference_code ||= Digest::MD5.hexdigest(Time.now.to_i.to_s + rand.to_s)
  end
  
  def set_root_from_reference_code(code)
    root = CourseConfig.first(:reference_code => code)
    if root
      self.root_id = root.id
    else
      self.root_id = nil
    end
  end
  
  def settings_hash
    @hash ||= JSON.parse(self.settings || "{}")
  end
  
  def configured?
    settings_hash && settings_hash['badge_url'] && settings_hash['min_percent']
  end
  
  def modules_required?
    settings_hash && settings_hash['modules']
  end
  
  def required_modules
    (settings_hash['modules'] || [])
  end
  
  def required_module_ids
    (settings_hash['modules'] || []).map(&:first).map(&:to_i)
  end
  
  def required_modules_completed?(completed_module_ids)
    incomplete_module_ids = self.required_module_ids - completed_module_ids
    incomplete_module_ids.length == 0
  end
  
  def required_score_met?(percent)
    percent >= settings_hash['min_percent']
  end
  
  def requirements_met?(percent, completed_module_ids)
    required_modules_completed?(completed_module_ids) && required_score_met?(percent)
  end
end

class Badge
  include DataMapper::Resource
  property :id, Serial
  property :course_id, String
  property :user_id, String
  property :domain_id, Integer
  property :badge_url, String, :length => 256
  property :nonce, String
  property :course_config_id, Integer
  property :name, String, :length => 256
  property :user_full_name, String, :length => 256
  property :description, Text
  property :recipient, String, :length => 512
  property :salt, String, :length => 256
  property :issued, DateTime
  property :email, String
  property :manual_approval, Boolean
  property :public, Boolean
  property :state, String
  property :global_user_id, String, :length => 256
  
  belongs_to :course_config
  before :save, :generate_defaults
  
  def generate_defaults
    self.salt ||= Time.now.to_i.to_s
    self.nonce ||= Digest::MD5.hexdigest(self.salt + rand.to_s)
    self.issued ||= DateTime.now if self.awarded?
    if !self.recipient
      sha = Digest::SHA256.hexdigest(self.email + self.salt)
      self.recipient = "sha256$#{sha}"
    end
    self.course_config ||= CourseConfig.first(:course_id => self.course_id, :domain_id => self.domain_id)
    user_config = UserConfig.first(:user_id => self.user_id, :domain_id => self.domain_id)
    self.global_user_id = user_config.global_user_id if user_config
    true
  end
  
  def user_name
    conf = UserConfig.first(:user_id => self.user_id, :domain_id => self.domain_id)
    (conf && conf.name) || self.user_full_name
  end
  
  def course_nonce
    self.course_config ||= CourseConfig.first(:course_id => self.course_id, :domain_id => self.domain_id)
    self.course_config.root_nonce
  end
  
  def awarded?
    self.state == 'awarded'
  end
  
  def pending?
    self.state == 'pending'
  end
  
  def revoke
    self.state = 'revoked'
    save
  end
  
  def award
    self.state = 'awarded'
    save
  end
  
  def self.generate_badge(params, course_config, name, email)
    settings = course_config.settings_hash
    badge = self.first_or_new(:user_id => params['user_id'], :course_id => params['course_id'], :domain_id => params['domain_id'])
    badge.name = settings['badge_name']
    badge.email = email
    badge.user_full_name = name || params['user_name']
    badge.description = settings['badge_description']
    badge.badge_url = settings['badge_url']
    badge
  end
  
  def self.manually_award(params, course_config, name, email)
    badge = generate_badge(params, course_config, name, email)
    badge.manual_approval = true unless badge.pending?
    badge.state = 'awarded'
    badge.issued = DateTime.now
    badge.save
    badge
  end
  
  def self.complete(params, course_config, name, email)
    settings = course_config.settings_hash
    badge = generate_badge(params, course_config, name, email)
    badge.state ||= settings['manual_approval'] ? 'pending' : 'awarded'
    badge.save
    badge
  end
end

module Sinatra
  module Models
    configure do  
      env = ENV['RACK_ENV'] || settings.environment
      DataMapper.setup(:default, (ENV["DATABASE_URL"] || "sqlite3:///#{Dir.pwd}/#{env}.sqlite3"))
      DataMapper.auto_upgrade!
      @@oauth_config = ExternalConfig.first(:config_type => 'canvas_oauth')
    end
    
    def oauth_config
      @@oauth_config
    end
  end
  
  register Models
end
