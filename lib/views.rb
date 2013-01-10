require 'sinatra/base'

module Sinatra
  module Views
    get "/" do
      erubis :index
    end
    
    get "/canvabadges.xml" do
      response.headers['Content-Type'] = "text/xml"
      erubis :config_xml, :layout => false
    end

    # public page that shows requirements for badge completion
    get "/badges/criteria/:course_nonce" do
      @course_config = CourseConfig.first(:nonce => params['course_nonce'])
      if !@course_config
        return error("Badge not found")
      end
      @badge = Badge.first(:nonce => params['user'])
      @earned = params['user'] && @badge && @badge.course_nonce == params['course_nonce']
      erubis :badge_completion
    end
    
    # show all public badges for the specified user
    get "/badges/all/:domain_id/:user_id" do
      @for_current_user = session['user_id'] == params['user_id'] && session['domain_id'] == params['domain_id']
      @badges = Badge.all(:user_id => params['user_id'], :domain_id => params['domain_id'], :state => 'awarded')
      @badges = @badges.select{|b| b.public } unless @for_current_user
      @domain = Domain.first(:id => params['domain_id'])
      @user = UserConfig.first(:user_id => params['user_id'], :domain_id => params['domain_id'])
      erubis :user_badges
    end
    
    # the magic page, APIs it up to make sure the user has done what they need to,
    # shows the results and lets them add the badge if they're done
    get "/badges/check/:domain_id/:course_id/:user_id" do
      if params['user_id'] != session['user_id'] || !session["permission_for_#{params['course_id']}"]
        return error("Invalid tool load #{session.to_json}")
      end
      @user_config = UserConfig.first(:user_id => params['user_id'], :domain_id => params['domain_id'])
      if @user_config
        @course_config = CourseConfig.first(:course_id => params['course_id'], :domain_id => params['domain_id'])
        if @course_config && @course_config.configured?
          scores_json = api_call("/api/v1/courses/#{params['course_id']}?include[]=total_scores", @user_config)
          modules_json = api_call("/api/v1/courses/#{params['course_id']}/modules", @user_config) if @course_config.modules_required?
          modules_json ||= []
          @completed_module_ids = modules_json.select{|m| m['completed_at'] }.map{|m| m['id'] }.compact
          unless scores_json
            return error("No data")
          end
          
          @student = scores_json['enrollments'].detect{|e| e['type'] == 'student' }
          @student['computed_final_score'] ||= 0 if @student
          @badge = nil

          if @student
            if @course_config.requirements_met?(@student['computed_final_score'], @completed_module_ids)
              @badge = Badge.complete(params, @course_config, session['name'], session['email'])
            end
          end
          erubis :badge_check
        else
          if session["permission_for_#{params['course_id']}"] == 'edit'
            erubis :manage_badge
          else
            return message("Your teacher hasn't set up this badge yet")
          end
        end
      else
        return error("Invalid user session")
      end
    end
    
    helpers do      
      def edit_course_html(domain_id, course_id, user_id, user_config, course_config)
        @domain_id = domain_id
        @course_id = course_id
        @user_config = user_config
        @course_config = course_config
        @modules_json ||= api_call("/api/v1/courses/#{course_id}/modules", user_config)
        erubis :_badge_settings
      end
      
      def error(text)
        message(text)
      end
      
      def message(text)
        @message = text
        return erubis :message
      end
    end
  end
  
  register Views
end
