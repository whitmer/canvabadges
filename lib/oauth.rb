require 'sinatra/base'

module Sinatra
  module OAuth
    # LTI tool launch, makes sure we're oauth-good and then redirects to the magic page
    post "/badge_check" do
      key = params['oauth_consumer_key']
      tool_config = ExternalConfig.first(:config_type => 'lti', :value => key)
      if !tool_config
        return error("Invalid tool launch - unknown tool consumer")
      end
      secret = tool_config.shared_secret
      host = params['tool_consumer_instance_guid'].split(/\./)[1..-1].join(".") if params['tool_consumer_instance_guid'] && params['tool_consumer_instance_guid'].match(/\./)
      domain = Domain.first(:host => host)
      domain ||= Domain.new(:host => host)
      domain.name = params['tool_consumer_instance_name']
      domain.save
      provider = IMS::LTI::ToolProvider.new(key, secret, params)
      if !params['custom_canvas_user_id'] || !params['custom_canvas_course_id']
        return error("Course must be a Canvas course, and launched with public permission settings")
      end
      if provider.valid_request?(request)
        user_id = params['custom_canvas_user_id']
        user_config = UserConfig.first(:user_id => user_id, :domain_id => domain.id)
        session["user_id"] = user_id
        session["launch_course_id"] = params['custom_canvas_course_id']
        session["permission_for_#{params['custom_canvas_course_id']}"] = 'view'
        session['email'] = params['lis_person_contact_email_primary']
        # TODO: something akin to this parameter needs to be sent in order to
        # tell the difference between Canvas Cloud and Canvas CV instances.
        # Otherwise I can't tell the difference between global_user_id 5 from
        # Cloud as opposed to from CV.
        session['source_id'] = params['custom_canvas_system_id'] || 'cloud'
        session['name'] = params['lis_person_name_full']
        # check if they're a teacher or not
        session["permission_for_#{params['custom_canvas_course_id']}"] = 'edit' if provider.roles.include?('instructor') || provider.roles.include?('contentdeveloper') || provider.roles.include?('urn:lti:instrole:ims/lis/administrator') || provider.roles.include?('administrator')
        session['domain_id'] = domain.id.to_s
        # if we already have an oauth token then we're good
        if user_config
          session['user_id'] = user_config.user_id
          if params['custom_show_all']
            redirect to("/badges/all/#{domain.id}/#{user_config.user_id}")
          else
            redirect to("/badges/check/#{domain.id}/#{params['custom_canvas_course_id']}/#{user_config.user_id}")
          end
        # otherwise we need to do the oauth dance for this user
        else
          oauth_dance(request, host)
        end
      else
        return error("Invalid tool launch - invalid parameters")
      end
    end

    get "/oauth_success" do
      if !session['domain_id'] || !session['user_id'] || !session['launch_course_id'] || !session['source_id']
        return error("Launch parameters lost")
      end
      domain = Domain.first(:id => session['domain_id'])
      return_url = "#{BadgeHelpers.protocol}://#{request.host_with_port}/oauth_success"
      code = params['code']
      url = "#{BadgeHelpers.protocol}://#{domain.host}/login/oauth2/token"
      uri = URI.parse(url)
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = BadgeHelpers.protocol == "https"
      request = Net::HTTP::Post.new(uri.request_uri)
      request.set_form_data({
        :client_id => BadgeHelpers.oauth_config.value,
        :code => code,
        :client_secret => BadgeHelpers.oauth_config.shared_secret,
        :redirect_uri => CGI.escape(return_url)
      })
      response = http.request(request)
      json = JSON.parse(response.body)
      puts "retrieving token from #{url}..."
      puts response.body
      
      if json && json['access_token']
        user_config = UserConfig.first(:user_id => session['user_id'], :domain_id => domain.id)
        user_config ||= UserConfig.new(:user_id => session['user_id'], :domain_id => domain.id)
        user_config.access_token = json['access_token']
        user_config.name = session['name']
        user_config.global_user_id = session['source_id'] + "_" + json['user']['id'].to_s
        user_config.save
        redirect to("/badges/check/#{domain.id}/#{session['launch_course_id']}/#{user_config.user_id}")
        session.destroy
        session['user_id'] = user_config.user_id.to_s
        session['domain_id'] = user_config.domain_id.to_s
      else
        return error("Error retrieving access token")
      end
    end
  end
  
  register OAuth
end
