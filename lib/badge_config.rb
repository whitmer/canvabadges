require 'sinatra/base'

module Sinatra
  module BadgeConfig
    # configure badge settings.
    # eventually the teacher will also use this to configure badge acceptance criteria
    post "/badges/settings/:domain_id/:course_id" do
      if session["permission_for_#{params['course_id']}"] == 'edit'
        course_config = CourseConfig.first(:course_id => params['course_id'], :domain_id => params['domain_id'])
        course_config ||= CourseConfig.new(:course_id => params['course_id'], :domain_id => params['domain_id'])
        settings = JSON.parse(course_config.settings || "{}")
        settings['badge_url'] = params['badge_url']
        settings['badge_url'] = "/badges/default.png" if !settings[:badge_url] || settings[:badge_url].empty?
        settings['badge_name'] = params['badge_name']
        settings['reference_code'] = params['reference_code']
        settings['badge_description'] = params['badge_description']
        settings['manual_approval'] = params['manual_approval'] == '1'
        settings['min_percent'] = params['min_percent'].to_f
        modules = []
        params.each do |k, v|
          if k.match(/module_/)
            modules << [k.sub(/module_/, ''), CGI.unescape(v)]
          end
        end
        settings['modules'] = modules.length > 0 ? modules : nil
        
        course_config.settings = settings.to_json
        course_config.set_root_from_reference_code(params['reference_code'])
        course_config.save
        redirect to("/badges/check/#{params['domain_id']}/#{params['course_id']}/#{session['user_id']}")
      else
        return error("You can't edit this")
      end
    end
    
    # set a badge to public or private
    post "/badges/:badge_id" do
      badge = Badge.first(:nonce => params['badge_id'])
      if badge.user_id == session['user_id']
        badge.public = params['public'] == 'true'
        badge.save
        badge.open_badge_json(request.host_with_port)
      else
        return {:error => "user mismatch"}.to_json
      end
    end
    
    # manually award a user with the course's badge
    post "/badges/award/:domain_id/:course_id/:user_id" do
      course_config = CourseConfig.first(:course_id => params['course_id'], :domain_id => params['domain_id'])
      user_config = UserConfig.first(:user_id => session['user_id'], :domain_id => params['domain_id'])
      settings = course_config && JSON.parse(course_config.settings || "{}")
      if course_config && settings && settings['badge_url'] && settings['min_percent']
        if session["permission_for_#{params['course_id']}"] != 'edit'
          return error("You don't have permission to award this badge")
        end
        json = BadgeHelpers.api_call("/api/v1/courses/#{params['course_id']}/users?enrollment_type=student&include[]=email&user_id=#{params['user_id']}", user_config)
        student = json.detect{|e| e['id'] == params['user_id'].to_i }
        if student
          badge = Badge.manually_award(params, course_config, student['name'], student['email'])
          
          redirect to("/badges/check/#{params['domain_id']}/#{params['course_id']}/#{session['user_id']}")
        else
          return error("That user is not a student in this course")
        end
      else
        return error("This badge has not been configured yet")
      end
    end
    
  end
  
  register BadgeConfig
end