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

class Badge
  include DataMapper::Resource
  property :id, Serial
  property :course_id, String
  property :user_id, String
  property :badge_url, String
  property :nonce, String
  property :recipient, String
  property :salt, String
  property :issued, DateTime
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
# example: http://localhost:4567/badge_check?oauth_consumer_key=1234&custom_canvas_user_id=1&custom_canvas_course_id=1&tool_consumer_instance_guid=bob.localhost:3000
# tool launch, makes sure we're oauth-good and then redirects to the magic page
post "/badge_check" do
  key = params['oauth_consumer_key']
  tool_config = ExternalConfig.first(:config_type => 'lti', :value => key)
  secret = tool_config.shared_secret
  provider = IMS::LTI::ToolProvider.new(key, secret, params)
  if !params['custom_canvas_user_id'] || !params['custom_canvas_course_id']
    return error("Course must be a Canvas course, and launched with public permission settings")
  end
  if true #provider.valid_request?(request)
    user_id = params['custom_canvas_user_id']
    user_config = UserConfig.first(:user_id => user_id)
    session['course_id'] = params['custom_canvas_course_id']
    session['user_id'] = user_id
    session['email'] = params['lis_person_contact_email_primary']
    # check if they're a teacher or not
    session['edit_privileges'] = true
    
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
    return error("Invalid tool launch")
  end
end

get "/oauth_success" do
  session['api_host'] ||= 'canvas.instructure.com'
  return_url = "https://#{request.host_with_port}/oauth_success"
  puts return_url
  code = params['code']
  url = "https://#{session['api_host']}/login/oauth2/token"
  puts url
  uri = URI.parse(url)
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.request_uri)
  request.set_form_data({
    :client_id => @@oauth_config.value,
    :code => code,
    :client_secret => @@oauth_config.shared_secret,
    :redirect_uri => CGI.escape(return_url)
  })
  puts "configured..."
  response = http.request(request)
  puts "response retrieved!"
  json = JSON.parse(response.body)
  
  if json && json['access_token']
    puts "making config"
    user_config = UserConfig.new
    user_config.user_id = session['user_id']
    user_config.token = json['access_token']
    user_config.host = session['api_host']
    user_config.save
    puts "config saved"
    redirect to("/badge_check/#{session['course_id']}/#{session['user_id']}")
  else
    return error("Error retrieving access token")
  end
end

get "/badges/:course_id/:user_id/:code" do
  badge = Badge.first(:course_id => params[:course_id], :user_id => params[:user_id], :nonce => params[:code])
  if badge
    return {
      :recipient => badge.recipient,
      :salt => badge.salt, 
      :issued_on => badge.issued.strftime("%Y-%m-%d"),
      :badge => {
        :version => "0.5.0",
        :name => badge.name,
        :image => badge.badge_url,
        :description => badge.description,
        :issuer => {
          :origin => "https://#{request.host_with_port}",
          :name => "Canvabadges",
          :org => "Instructure, Inc.",
          :contact => "support@instructure.com"
        }
      }
    }.to_json
  else
    return "Not Found"
  end
end

# eventually the teacher will use this to configure badge acceptance criteria
post "/badge_check/:course_id/:user_id/settings" do
  if params['course_id'] != session['course_id'] || params['user_id'] != session['user_id']
    return error("Invalid tool load")
  end
  if session['edit_privileges']
    course_config = CourseConfig.first(:course_id => params['course_id'])
    course_config ||= CourseConfig.new(:course_id => params['course_id'])
    settings = JSON.parse(course_config.settings || "{}")
    settings[:badge_url] = "/badges/instructure.png"
    settings[:badge_name] = params['badge_name']
    settings[:badge_description] = params['badge_description']
    settings[:min_percent] = params['min_percent'].to_f
    course_config.settings = settings.to_json
    course_config.save
    redirect to("/badge_check/#{params['course_id']}/#{session['user_id']}")
  else
    return error("You can't edit this")
  end
end

# the magic page, APIs it up to make sure the user has done what they need to,
# shows the results and lets them add the badge if they're done
get "/badge_check/:course_id/:user_id" do
  if params['course_id'] != session['course_id'] || params['user_id'] != session['user_id']
    return error("Invalid tool load")
  end
  user_config = UserConfig.first(:user_id => params['user_id'])
  if user_config
    course_config = CourseConfig.first(:course_id => params['course_id'])
    settings = course_config && JSON.parse(course_config.settings || "{}")
    if course_config && settings && settings['badge_url'] && settings['min_percent']
      url = "https://#{user_config.host}/api/v1/courses/#{params['course_id']}?include[]=total_scores&access_token=#{user_config.token}"
      json = JSON.parse(Net::HTTP.get(URI.parse(url)))
      student = json['enrollments'].detect{|e| e['type'] == 'student' && e['calculated_final_score'] }
      html = header
      if student
        badge = Badge.first(:user_id => params['user_id'], :course_id => params['course_id'])
        if !badge && student['calculated_final_score'] >= settings['min_percent']
          badge = Badge.new(:user_id => params['user_id'], :course_id => params['course_id'])
          badge.issued = DateTime.now
          badge.salt = Time.now.to_i.to_s
          sha = Digest::SHA512.hexdigest(session['email'] + badge.salt)
          badge.recipint = "sha512$#{sha}"
          badge.sig = Digest::MD5.hexdigest(badge.salt + rand.to_s)
        end
        html += "<img src='" + settings['badge_url'] + "' style='float: left;' class='thumbnail'/>"
        if badge
          html += "<h2>You've earned this badge!</h2>"
          html += "<div class='progress progress-success progress-striped progress-big'><div class='tick' style='left: " + (300 * settings['min_percent']) + "px;'></div><div class='bar' style='width: " + student['calculated_final_score'] + "%;'></div></div>"
          url = "https:///#{request.host_with_port}/badges/#{params['course_id']}/#{params['user_id']}/#{badge.nonce}"
          html += url
          html += "<script>OpenBadges.issue([\"#{url}\"]);</script>"
        else
          html += "<h2>You haven't earn this badge yet</h2>"
          html += "<div class='progress progress-danger progress-striped progress-big'><div class='tick' style='left: " + (300 * settings['min_percent']) + "px;'></div><div class='bar' style='width: " + student['calculated_final_score'] + "%;'></div></div>"
        end
      else
        html += "<h2>You are not a student in this course</h2>"
      end
      if session['edit_privileges']
        html += edit_course_html(params['course_id'], params['user_id'], course_config)
      end
      html += footer
      return html
    else
      if session['edit_privileges']
        return header + edit_course_html(params['course_id'], params['user_id'], course_config) + footer
      else
        return message("Your teacher hasn't set up this badge yet")
      end
    end
  else
    return error("Invalid user session")
  end
end

def edit_course_html(course_id, user_id, course_config)
  settings = JSON.parse((course_config && course_config.settings) || "{}")
  <<-HTML
    <form class='well form-horizontal' style="margin-top: 15px;" method="post" action="/badge_check/#{course_id}/#{user_id}/settings">
    <h2>Badge Settings</h2>
    <img src='/badges/instructure.png' style='float: left; margin-right: 10px;' class='thumbnail'/>
    <fieldset>
    <div class="control-group">
      <label class="control-label" for="badge_name">Badge name: </label>
      <div class="controls">
        <input type="text" class="span2" placeholder="name" id="badge_name" name="badge_name" value="#{CGI.escapeHTML(settings['badge_name'] || "")}"/>
      </div>
    </div>
    <div class="control-group">
      <label class="control-label" for="badge_description">Badge description: </label>
      <div class="controls">
        <input type="text" class="span2" placeholder="description" id="badge_description" name="badge_description" value="#{CGI.escapeHTML(settings['badge_description'] || "")}"/>
      </div>
    </div>
    <div class="control-group">
      <label class="control-label" for="min_percent">Final grade cutoff: </label>
      <div class="controls">
        <div class="input-append">
          <input type="text" class="span1" placeholder="##" id="min_percent" name="min_percent" value="#{settings['min_percent']}"/><span class='add-on'> % </span>
        </div>
      </div>
    </div>
    <div class="form-actions" style="border: 0; background: transparent;">
      <button type="submit" class='btn btn-primary'>Save Badge Settings</button>
    </div>
    </fieldset>
    </form> 
  HTML
end

def error(message)
  header + "<h2>" + message + "</h2>" + footer
end

def message(message)
  header + "<h2>" + message + "</h2>" + footer
end

def header
  <<-HTML
<html>
  <head>
    <meta charset="utf-8">
    <title>Canvabadges</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="">
    <meta name="author" content="">

    <!-- Le styles -->
    <link href="/bootstrap/css/bootstrap.css" rel="stylesheet">
    <link href="/bootstrap/css/bootstrap-responsive.css" rel="stylesheet">

    <!-- Le HTML5 shim, for IE6-8 support of HTML5 elements -->
    <!--[if lt IE 9]>
      <script src="http://html5shim.googlecode.com/svn/trunk/html5.js"></script>
    <![endif]-->

    <!-- Le fav and touch icons -->
    <link rel="shortcut icon" href="/bootstrap/ico/favicon.ico">
    <link rel="apple-touch-icon-precomposed" sizes="114x114" href="/bootstrap/ico/apple-touch-icon-114-precomposed.png">
    <link rel="apple-touch-icon-precomposed" sizes="72x72" href="/bootstrap/ico/apple-touch-icon-72-precomposed.png">
    <link rel="apple-touch-icon-precomposed" href="/bootstrap/ico/apple-touch-icon-57-precomposed.png">
    <style>
    .progress-big, .progress-big .bar {
      height: 40px;
    }
    .progress-big {
      width: 300px;
      position: relative;
    }
    .progress-big .tick {
      z-index: 2;
      width: 1px;
      border: 1px solid #000;
      height: 44px;
      top: -2px;
    }
    </style>
    <script src="http://beta.openbadges.org/issuer.js"></script>
  </head>
  <body>
    <div class="container" id="content">
    <div id="contents">
  HTML
end

def footer
  <<-HTML
    </div>
  </div>
  <script src="jquery.min.js"></script>
</body>
</html>
  HTML
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
