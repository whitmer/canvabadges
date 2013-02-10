begin
  require 'rubygems'
rescue LoadError
  puts "You must install rubygems to run this example"
  raise
end

begin
  require 'bundler/setup'
rescue LoadError
  puts "to set up this example, run these commands:"
  puts "  gem install bundler"
  puts "  bundle install"
  raise
end

require 'sinatra'
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
require './lib/badge_config.rb'
require './lib/views.rb'

# sinatra wants to set x-frame-options by default, disable it
disable :protection
# enable sessions so we can remember the launch info between http requests, as
# the user takes the assessment
enable :sessions

module BadgeHelpers
  def self.protocol
    (ENV['RACK_ENV'] || settings.environment).to_s == "development" ? "http" : "https"
  end
  
  def self.oauth_config
    @oauth_config ||= ExternalConfig.first(:config_type => 'canvas_oauth')
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

