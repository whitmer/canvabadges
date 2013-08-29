require 'sinatra/base'

module Sinatra
  module BadgeConfiguration
    def self.registered(app)
      app.helpers BadgeConfiguration::Helpers
      
      # configure badge settings.
      # eventually the teacher will also use this to configure badge acceptance criteria
      app.post "/badges/settings/:badge_config_id" do
        load_badge_config(params['badge_config_id'], 'edit')
        
        settings = @badge_config.settings || {}
        settings['badge_url'] = params['badge_url']
        settings['badge_url'] = "/badges/default.png" if !settings['badge_url'] || settings['badge_url'].empty?
        settings['badge_name'] = params['badge_name'] || "Badge"
        settings['reference_code'] = params['reference_code']
        settings['badge_description'] = params['badge_description'] || "No description"
        settings['badge_requirements'] = params['badge_requirements']
        settings['badge_hours'] = params['badge_hours'].to_f.round(1)
        settings['manual_approval'] = params['manual_approval'] == '1'
        settings['require_evidence'] = params['require_evidence'] == '1'
        settings['credit_based'] = params['credit_based'] == '1'
        settings['required_credits'] = params['requird_credits'].to_f.round(1)
        settings['min_percent'] = params['min_percent'].to_f
        settings['hours'] = params['hours'].to_f.round(1)
        settings['hours'] = nil if settings['hours'] == 0
        settings['credits_for_final_score'] = params['credits_for_final_score'].to_f.round(1)
        total_credits = settings['credits_for_final_score']
        modules = []
        params.each do |k, v|
          if k.match(/module_/)
            id = k.sub(/module_/, '').to_i
            if id > 0
              total_credits += params["credits_for_#{id}"].to_f.round(1)
              credits = params["credits_for_#{id}"].to_f.round(1)
              modules << [id, CGI.unescape(v), credits]
            end
          end
        end
        settings['modules'] = modules.length > 0 ? modules : nil
        settings['total_credits'] = total_credits
        
        @badge_config.settings = settings
        @badge_config.updated_at = DateTime.now
        @badge_config.public = params['public'] == '1'
        @badge_config.set_root_from_reference_code(params['reference_code'])
        @badge_config.save
        redirect to("/badges/check/#{@badge_config_id}/#{@user_id}")
      end
      
      # set a badge to public or private
      app.post "/badges/:badge_id" do
        badge = Badge.first(:nonce => params['badge_id'])
        if !badge
          halt 400, {:error => "invalid badge"}.to_json
        elsif badge.user_id == session['user_id']
          if params['public']
            badge.public = (params['public'] == 'true')
          end
          if params['evidence_url'] && !badge.awarded?
            badge.evidence_url = params['evidence_url']
          end
          badge.save
          {:id => badge.id, :nonce => badge.nonce, :public => badge.public}.to_json
        else
          halt 400, {:error => "user mismatch"}.to_json
        end
      end
      
      # manually award a user with the course's badge
      app.post "/badges/award/:badge_config_id/:user_id" do
        load_badge_config(params['badge_config_id'], 'edit')
  
        settings = (@badge_config && @badge_config.settings) || {}
        if settings && settings['badge_url'] && settings['min_percent']
          json = api_call("/api/v1/courses/#{@course_id}/users?enrollment_type=student&include[]=email&user_id=#{params['user_id']}", @user_config)
          student = json.detect{|e| e['id'] == params['user_id'].to_i }
          if student
            if !student['email']
              return error("That user doesn't have an email in Canvas, and so can't be awarded badges. Please notify the student that they need to set up an email address and then try again.")
            end
            badge = Badge.manually_award(params, @badge_config, student['name'], student['email'])
            
            redirect to("/badges/check/#{@badge_config_id}/#{@user_id}")
          else
            return error("That user is not a student in this course")
          end
        else
          return error("This badge has not been configured yet")
        end
      end
      
    end
  
    module Helpers
      def load_badge_config(badge_config_id, permission=nil)
        @badge_config = BadgeConfig.first(:id => badge_config_id)
        domain_id = @badge_config && @badge_config.domain_id
        @user_config = UserConfig.first(:domain_id => domain_id, :user_id => session['user_id'])
        if !@badge_config
          halt 404, error("Configuration not found")
        end

        @badge = Badge.first(:badge_config_id => @badge_config.id, :user_id => session['user_id'])
        @course_id = @badge_config.course_id
        if permission
          if !session['user_id']
            halt 400, error("Session information lost")
          elsif permission == 'view'
            halt 404, error("Insufficient permissions") if !session["permission_for_#{@course_id}"]
          elsif permission == 'edit'
            halt 404, error("Insufficient permissions") if session["permission_for_#{@course_id}"] != 'edit'
          end
        end
        @admin = session["permission_for_#{@course_id}"] == 'edit'
        @placement_id = @badge_config.placement_id
        @badge_config_id = @badge_config.id
        @domain_id = @badge_config.domain_id || domain_id
        @user_id = session['user_id']
      end
    end
  end
  
  register BadgeConfiguration
end