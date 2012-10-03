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

require './lib/models.rb'
require './lib/oauth.rb'
require './lib/badge_data.rb'
require './lib/badge_config.rb'
require './lib/views.rb'
require './lib/config.rb'

# sinatra wants to set x-frame-options by default, disable it
disable :protection
# enable sessions so we can remember the launch info between http requests, as
# the user takes the assessment
enable :sessions

get "/" do
  return message("Canvabadges are cool")
end

def oauth_dance(request, host)
  return_url = "https://#{request.host_with_port}/oauth_success"
  redirect to("https://#{host}/login/oauth2/auth?client_id=#{oauth_config.value}&response_type=code&redirect_uri=#{CGI.escape(return_url)}")
end
    

def api_call(path, user_config, post_params=nil)
  url = "https://#{user_config.host}/" + path
  url += (url.match(/\?/) ? "&" : "?") + "access_token=#{user_config.access_token}"
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  req = Net::HTTP::Get.new(uri.request_uri)
  response = http.request(req)
  json = JSON.parse(response.body)
  if response.code != "200"
    puts response.body
    oauth_dance(request, user_config.host)
    false
  else
    json
  end
end

