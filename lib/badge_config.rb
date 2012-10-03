require 'sinatra/base'

module Sinatra
  module BadgeConfig
    # eventually the teacher will use this to configure badge acceptance criteria
    post "/badge_check/:course_id/:user_id/settings" do
      if params['user_id'] != session['user_id'] || !session["permission_for_#{params['course_id']}"]
        return error("Invalid tool load")
      end
      if session["permission_for_#{params['course_id']}"] == 'edit'
        course_config = CourseConfig.first(:course_id => params['course_id'])
        course_config ||= CourseConfig.new(:course_id => params['course_id'])
        settings = JSON.parse(course_config.settings || "{}")
        settings[:badge_url] = params['badge_url']
        settings[:badge_url] = "/badges/default.png" if !settings[:badge_url] || settings[:badge_url].empty?
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
    
    # manually award a user with the course's badge
    post "/badges/:course_id/:user_id" do
      course_config = CourseConfig.first(:course_id => params['course_id'])
      user_config = UserConfig.first(:user_id => session['user_id'])
      settings = course_config && JSON.parse(course_config.settings || "{}")
      if course_config && settings && settings['badge_url'] && settings['min_percent']
        if session["permission_for_#{params['course_id']}"] != 'edit'
          return error("You don't have permission to award this badge")
        end
        json = api_call("/api/v1/courses/#{params['course_id']}/users?enrollment_type=student&include[]=email", user_config)
        student = json.detect{|e| e['id'] == params['user_id'].to_i }
        if student
          badge = Badge.first(:user_id => params['user_id'], :course_id => params['course_id'])
          badge ||= Badge.new(:user_id => params['user_id'], :course_id => params['course_id'])
          badge.name = settings['badge_name']
          badge.description = settings['badge_description']
          badge.badge_url = settings['badge_url']
          badge.issued = DateTime.now
          badge.salt = Time.now.to_i.to_s
          badge.email = student['email']
          sha = Digest::SHA256.hexdigest(student['email'] + badge.salt)
          badge.recipient = "sha256$#{sha}"
          badge.nonce = Digest::MD5.hexdigest(badge.salt + rand.to_s)
          badge.manual_approval = true
          badge.save
          
          redirect to("/badge_check/#{params['course_id']}/#{session['user_id']}")
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