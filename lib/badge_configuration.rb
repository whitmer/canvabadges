require 'sinatra/base'

module Sinatra
  module BadgeConfiguration
    def self.registered(app)
      app.helpers BadgeConfiguration::Helpers
      
      # Link selection page for picking from existing badges or making a new one
      app.get "/badges/pick" do
        org_check
        load_user_config
        halt 404, error("No user information found") unless @user_config
        @badge_configs = BadgeConfigOwner.all(:user_config_id => @user_config.id, :order => :id.desc).map(&:badge_config).uniq
        erb :badge_chooser        
      end
      
      # configure badge settings.
      app.post "/badges/settings/:badge_placement_config_id" do
        load_badge_config(params['badge_placement_config_id'], 'edit')
        
        @badge_config = @badge_placement_config.badge_config
        raise "bad!" unless @badge_config
        placement_settings = @badge_placement_config.settings || {}
        badge_settings = @badge_config.settings || {}
        
        badge_settings['badge_url'] = params['badge_url']
        badge_settings['badge_url'] = "/badges/default.png" if !badge_settings['badge_url'] || badge_settings['badge_url'].empty?
        badge_settings['badge_name'] = params['badge_name'] || "Badge"
        badge_settings['badge_description'] = params['badge_description'] || "No description"
        badge_settings['badge_requirements'] = params['badge_requirements']
        badge_settings['badge_hours'] = params['badge_hours'].to_f.round(1)
        placement_settings['manual_approval'] = params['manual_approval'] == '1'
        placement_settings['require_evidence'] = params['require_evidence'] == '1'
        placement_settings['credit_based'] = params['credit_based'] == '1'
        placement_settings['required_credits'] = [params['required_credits'].to_f.round(1), 0.1].max
        placement_settings['min_percent'] = params['min_percent'].to_f
        placement_settings['hours'] = params['hours'].to_f.round(1)
        placement_settings['hours'] = nil if placement_settings['hours'] == 0
        placement_settings['pending'] = false
        placement_settings['award_only'] = false
        placement_settings['credits_for_final_score'] = params['credits_for_final_score'].to_f.round(1)
        total_credits = placement_settings['credits_for_final_score']
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
        placement_settings['modules'] = modules.length > 0 ? modules : nil
        placement_settings['total_credits'] = total_credits
        
        @badge_placement_config.settings = placement_settings
        @badge_placement_config.updated_at = DateTime.now
        @badge_placement_config.check_for_public_state

        if @user_config
          BadgeConfigOwner.first_or_create(:user_config_id => @user_config.id, :badge_config_id => @badge_config.id, :badge_placement_config_id => @badge_placement_config.id)
        end
        @badge_placement_config.author_user_config_id ||= @user_config.id if @user_config
        @badge_placement_config.save
        @badge_config.settings = badge_settings
        @badge_config.updated_at = DateTime.now
        @badge_config.public = params['public'] == '1'
        @badge_config.save
        redirect to("/badges/check/#{@badge_placement_config_id}/#{@user_id}")
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
      
      app.post "/badges/disable/:badge_placement_config_id" do
        load_badge_config(params['badge_placement_config_id'], 'edit')
        settings = @badge_placement_config.settings
        settings['pending'] = true
        @badge_placement_config.settings = settings
        @badge_placement_config.save
        {:disabled => true}.to_json
      end
      
      # manually award a user with the course's badge
      app.post "/badges/award/:badge_placement_config_id/:user_id" do
        load_badge_config(params['badge_placement_config_id'], 'edit')
        @badge_config = @badge_placement_config.badge_config
  
        settings = (@badge_placement_config && @badge_placement_config.merged_settings) || {}
        if @badge_config && @badge_config.configured? && (@badge_placement_config.configured? || @badge_placement_config.award_only?)
          json = api_call("/api/v1/courses/#{@course_id}/users?enrollment_type=student&include[]=email&user_id=#{params['user_id']}", @user_config)
          student = json.detect{|e| e['id'] == params['user_id'].to_i }
          if student
            if !student['email']
              return error("That user doesn't have an email in Canvas, and so can't be awarded badges. Please notify the student that they need to set up an email address and then try again.")
            end
            badge = Badge.manually_award(params, @badge_placement_config, student['name'], student['email'])
            
            redirect to("/badges/check/#{@badge_placement_config_id}/#{@user_id}")
          else
            return error("That user is not a student in this course")
          end
        else
          return error("This badge has not been configured yet")
        end
      end
      
    end
  
    module Helpers
      def load_user_config
        domain_id = @badge_placement_config && @badge_placement_config.domain_id
        domain_id ||= session['domain_id']
        @user_config = UserConfig.first(:domain_id => domain_id, :user_id => session['user_id']) if domain_id
      end
      
      def permission_check(course_id, permission)
        if permission
          if !session['user_id']
            halt 400, error("Session information lost")
          elsif permission == 'view'
            halt 404, error("Insufficient permissions") if !session["permission_for_#{course_id}"]
          elsif permission == 'edit'
            halt 404, error("Insufficient permissions") if session["permission_for_#{course_id}"] != 'edit'
          end
        end
      end
      
      def load_badge_config(badge_placement_config_id, permission=nil)
        @badge_placement_config = BadgePlacementConfig.first(:id => badge_placement_config_id)
        domain_id = @badge_placement_config && @badge_placement_config.domain_id
        load_user_config
        if !@badge_placement_config
          halt 404, error("Configuration not found")
        end

        @badge = Badge.first(:badge_config_id => @badge_placement_config.badge_config_id, :user_id => session['user_id'], :domain_id => domain_id)
        @course_id = @badge_placement_config.course_id
        @earned_for_different_course = @badge && @badge.badge_placement_config_id != @badge_placement_config.id
        permission_check(@course_id, permission)
        @admin = session["permission_for_#{@course_id}"] == 'edit'
        @placement_id = @badge_placement_config.placement_id
        @badge_placement_config_id = @badge_placement_config.id
        @badge_config_id = @badge_placement_config.badge_config_id
        @domain_id = @badge_placement_config.domain_id || domain_id
        @user_id = session['user_id']
        @badge_placement_config
      end
    end
  end
  
  register BadgeConfiguration
end