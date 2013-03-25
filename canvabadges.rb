require 'sinatra/base'
require 'oauth'
require 'json'
require 'dm-core'
require 'dm-migrations'
require 'nokogiri'
require 'oauth/request_proxy/rack_request'
require 'ims/lti'
require 'digest/md5'
require 'net/http'

require './lib/models.rb'
require './lib/oauth.rb'
require './lib/api.rb'
require './lib/badge_configuration.rb'
require './lib/views.rb'

class Canvabadges < Sinatra::Base
  register Sinatra::OAuth
  register Sinatra::Api
  register Sinatra::BadgeConfiguration
  register Sinatra::Views
  
  # sinatra wants to set x-frame-options by default, disable it
  disable :protection
  # enable sessions so we can remember the launch info between http requests, as
  # the user takes the assessment
  enable :sessions
  raise "session key required" if ENV['RACK_ENV'] == 'production' && !ENV['SESSION_KEY']
  set :session_secret, ENV['SESSION_KEY'] || "local_secret"

  env = ENV['RACK_ENV'] || settings.environment
  DataMapper.setup(:default, (ENV["DATABASE_URL"] || "sqlite3:///#{Dir.pwd}/#{env}.sqlite3"))
  DataMapper.auto_upgrade!
end

module BadgeHelpers
  def self.protocol
    ENV['RACK_ENV'].to_s == "development" ? "http" : "https"
  end
  
  def self.oauth_config
    @oauth_config ||= ExternalConfig.first(:config_type => 'canvas_oauth')
    raise "Missing oauth config" unless @oauth_config
    @oauth_config
  end
  
  def self.api_call(path, user_config, post_params=nil)
    url = "#{protocol}://#{user_config.host}" + path
    url += (url.match(/\?/) ? "&" : "?") + "access_token=#{user_config.access_token}"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    puts "API"
    puts url
    http.use_ssl = protocol == "https"
    req = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(req)
    json = JSON.parse(response.body)
    puts response.body
    json.instance_variable_set('@has_more', (response['Link'] || '').match(/rel=\"next\"/))
    if response.code != "200"
      puts "bad response"
      puts response.body
      oauth_dance(request, user_config.host)
      false
    else
      json
    end
  end
end

