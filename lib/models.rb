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
  property :description, String, :length => 256
  property :recipient, String, :length => 512
  property :salt, String, :length => 256
  property :issued, DateTime
  property :email, String
  property :manual_approval, Boolean
  property :public, Boolean
  
  belongs_to :course_config
  before :save, :generate_defaults
  
  def generate_defaults
    self.salt ||= Time.now.to_i.to_s
    self.nonce ||= Digest::MD5.hexdigest(self.salt + rand.to_s)
    if !self.recipient
      sha = Digest::SHA256.hexdigest(self.email + self.salt)
      self.recipient = "sha256$#{sha}"
    end
    self.course_config ||= CourseConfig.first(:course_id => self.course_id, :domain_id => self.domain_id)
  end
  
  def user_name
    conf = UserConfig.first(:user_id => self.user_id, :domain_id => self.domain_id)
    (conf && conf.name) || self.user_full_name
  end
  
  def course_nonce
    self.course_config.root_nonce
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
