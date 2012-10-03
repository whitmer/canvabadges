require 'dm-core'
require 'dm-migrations'
require 'sinatra/base'

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
  property :host, String
end

class CourseConfig
  include DataMapper::Resource
  property :id, Serial
  property :course_id, String
  property :settings, Text
end

class Badge
  include DataMapper::Resource
  property :id, Serial
  property :course_id, String
  property :user_id, String
  property :badge_url, String, :length => 256
  property :nonce, String
  property :name, String, :length => 256
  property :description, String, :length => 256
  property :recipient, String, :length => 512
  property :salt, String, :length => 256
  property :issued, DateTime
  property :email, String
  property :manual_approval, Boolean
end

module Sinatra
  module Models
    configure do  
      env = ENV['RACK_ENV'] || settings.environment
      DataMapper.setup(:default, (ENV["DATABASE_URL"] || "sqlite3:///#{Dir.pwd}/#{env}.sqlite3"))
      DataMapper.auto_upgrade!
      @@oauth_config = ExternalConfig.first(:config_type => 'canvas_oauth')
    end
  end
  
  register Models
end
