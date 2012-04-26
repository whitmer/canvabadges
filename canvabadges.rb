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

# hard-coded oauth information for testing convenience
$oauth_key = "test"
$oauth_secret = "secret"

# sinatra wants to set x-frame-options by default, disable it
disable :protection
# enable sessions so we can remember the launch info between http requests, as
# the user takes the assessment
enable :sessions

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
  property :token, String
  property :host, String
end

class CourseConfig
  include DataMapper::Resource
  property :id, Serial
  property :course_id, String
  property :settings, Text
end

configure do
  DataMapper.setup(:default, (ENV["DATABASE_URL"] || "sqlite3:///#{Dir.pwd}/development.sqlite3"))
  DataMapper.auto_upgrade!
  @@oauth_config = ExternalConfig.first(:config_type => 'canvas_oauth')
end

get "/" do
  redirect to('/index.html')
end

# example: https://canvabadges.heroku.com/badge_check?oauth_consumer_key=1234&custom_canvas_user_id=2&custom_canvas_course_id=2&tool_consumer_instance_guid=bob.canvas.instructure.com
# tool launch, makes sure we're oauth-good and then redirects to the magic page
get "/badge_check" do
  key = params['oauth_consumer_key']
  tool_config = ExternalConfig.first(:config_type => 'lti', :value => key)
  secret = tool_config.shared_secret
  provider = IMS::LTI::ToolProvider.new(key, secret, params)
  if !params['custom_canvas_user_id'] || !params['custom_canvas_course_id']
    return "Course must be a Canvas course, and launched with public permission settings"
  end
  if true #provider.valid_request?(request)
    user_id = params['custom_canvas_user_id']
    user_config = UserConfig.first(:user_id => user_id)
    session['course_id'] = params['custom_canvas_course_id']
    session['user_id'] = user_id
    # check if they're a teacher or not
    session['edit_privileges'] = false
    
    # if we already have an oauth token then we're good
    if user_config
      redirect to("/badge_check/#{session['course_id']}/#{session['user_id']}")
    # otherwise we need to do the oauth dance for this user
    else
      host = params['tool_consumer_instance_guid'].split(/\./)[1..-1].join(".")
      session['api_host'] = host
      return_url = "https://#{request.host_with_port}/oauth_success"
      redirect to("https://#{host}/login/oauth2/auth?client_id=#{@@oauth_config.value}&response_type=code&redirect_uri=#{CGI.escape(return_url)}")
    end
  else
    return "Invalid tool launch"
  end
end

get "/oauth_success" do
  return_url = "https://#{request.host_with_port}/oauth_success"
  code = params['code']
  url = "https://#{session['api_host']}/login/oauth2/token"
  uri = URI.parse(url)
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.request_uri)
  request.set_form_data({
    :client_id => @@oauth_config.value,
    :code => params['code'],
    :client_secret => @@oauth_config.shared_secret,
    :redirect_uri => CGI.escape(return_url)
  })
  response = http.request(request)
  json = JSON.parse(response.body)
  
  user_config = UserConfig.new
  user_config.user_id = session['user_id']
  user_config.token = json['access_token']
  user_config.host = session['api_host']
  user_config.save
  redirect to("/badge_check/#{session['course_id']}/#{session['user_id']}")
end


# the magic page, APIs it up to make sure the user has done what they need to,
# shows the results and lets them add the badge if they're done
get "/badge_check/:course_id/:user_id" do
  user_config = UserConfig.first(:user_id => params['user_id'])
  if user_config
    course_config = CourseConfig.first(:course_id => params['course_id'])
    settings = course_config && JSON.parse(course_config.settings || "{}")
    if course_config && settings && settings['icon_url']
      # check for mastery, teacher edit view
      return "Now checking on your coolness..."
    else
      if session['edit_privileges']
        # teacher create view
        return "Please decide what makes someone cool..."
      else
        return "Your teacher hasn't set up this badge yet"
      end
    end
  else
    return "Invalid user session"
  end
end

# eventually the teacher will use this to configure badge acceptance criteria
post "/badge_check/:course_id/settings" do
  if session['edit_privileges']
    course_config = CourseConfig.first(:course_id => params['course_id'])
    course_config ||= CourseConfig.new(:course_id => params['course_id'])
    settings = JSON.parse(course_config.settings || "{}")
    settings[:icon_url] = ""
    settings[:min_percent] = ""
    course_config.settings = settings.to_json
    course_config.save
    redirect to("/badge_check/#{params['course_id']}/#{session['user_id']}")
  else
    return "You can't edit this"
  end
end

def config_wrap(xml)
  res = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
  <cartridge_basiclti_link xmlns="http://www.imsglobal.org/xsd/imslticc_v1p0"
      xmlns:blti = "http://www.imsglobal.org/xsd/imsbasiclti_v1p0"
      xmlns:lticm ="http://www.imsglobal.org/xsd/imslticm_v1p0"
      xmlns:lticp ="http://www.imsglobal.org/xsd/imslticp_v1p0"
      xmlns:xsi = "http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation = "http://www.imsglobal.org/xsd/imslticc_v1p0 http://www.imsglobal.org/xsd/lti/ltiv1p0/imslticc_v1p0.xsd
      http://www.imsglobal.org/xsd/imsbasiclti_v1p0 http://www.imsglobal.org/xsd/lti/ltiv1p0/imsbasiclti_v1p0.xsd
      http://www.imsglobal.org/xsd/imslticm_v1p0 http://www.imsglobal.org/xsd/lti/ltiv1p0/imslticm_v1p0.xsd
      http://www.imsglobal.org/xsd/imslticp_v1p0 http://www.imsglobal.org/xsd/lti/ltiv1p0/imslticp_v1p0.xsd">
  XML
  res += xml
  res += <<-XML
      <cartridge_bundle identifierref="BLTI001_Bundle"/>
      <cartridge_icon identifierref="BLTI001_Icon"/>
  </cartridge_basiclti_link>  
  XML
end


post "/tool_redirect" do
  url = params['url']
  args = []
  params.each do |key, val|
    args << "#{CGI.escape(key)}=#{CGI.escape(val)}" if key.match(/^custom_/) || ['launch_presentation_return_url', 'selection_directive'].include?(key)
  end
  url = url + (url.match(/\?/) ? "&" : "?") + args.join('&')
  redirect to(url)
end
