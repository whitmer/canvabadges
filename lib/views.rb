require 'sinatra/base'

module Sinatra
  module Views
    def self.registered(app)
      app.helpers Views::Helpers
      
      app.get "/" do
        erb :index
      end
      
      app.get "/canvabadges.xml" do
        response.headers['Content-Type'] = "text/xml"
        erb :config_xml, :layout => false
      end
  
      # public page that shows requirements for badge completion
      app.get "/badges/criteria/:config_nonce" do
        @badge_config = BadgeConfig.first(:nonce => params['config_nonce'])
        if !@badge_config
          return error("Badge not found")
        end
        @badge = Badge.first(:nonce => params['user'])
        @earned = params['user'] && @badge && @badge.config_nonce == params['config_nonce']
        erb :badge_completion
      end
      
      # show all public badges for the specified user
      app.get "/badges/all/:domain_id/:user_id" do
        @for_current_user = session['user_id'] == params['user_id'] && session['domain_id'] == params['domain_id']
        @badges = Badge.all(:user_id => params['user_id'], :domain_id => params['domain_id'], :state => 'awarded')
        @badges = @badges.select{|b| b.public } unless @for_current_user
        @domain = Domain.first(:id => params['domain_id'])
        @user = UserConfig.first(:user_id => params['user_id'], :domain_id => params['domain_id'])
        erb :user_badges
      end
      
      # the magic page, APIs it up to make sure the user has done what they need to,
      # shows the results and lets them add the badge if they're done
      app.get "/badges/check/:domain_id/:placement_id/:user_id" do
        load_badge_config(params['domain_id'], params['placement_id'], 'view')
        if @badge_config && @badge_config.configured?
          scores_json = api_call("/api/v1/courses/#{@course_id}?include[]=total_scores", @user_config)
          modules_json = api_call("/api/v1/courses/#{@course_id}/modules", @user_config) if @badge_config.modules_required?
          modules_json ||= []
          @completed_module_ids = modules_json.select{|m| m['completed_at'] }.map{|m| m['id'] }.compact
          unless scores_json
            return error("No data")
          end
          
          @student = scores_json['enrollments'].detect{|e| e['type'] == 'student' }
          @student['computed_final_score'] ||= 0 if @student
          @badge = nil
          
          if @student
            if @badge_config.requirements_met?(@student['computed_final_score'], @completed_module_ids)
              @badge = Badge.complete(params, @badge_config, session['name'], session['email'])
            end
          end
          erb :badge_check
        else
          if session["permission_for_#{@course_id}"] == 'edit'
            erb :manage_badge
          else
            return message("Your teacher hasn't set up this badge yet")
          end
        end
      end
    end
    
    module Helpers
      def edit_course_html
        raise "no user" unless @user_config
        raise "missing value" unless @domain_id && @placement_id && @course_id && @badge_config
        @modules_json ||= api_call("/api/v1/courses/#{@course_id}/modules", @user_config)
        erb :_badge_settings
      end
      
      def error(text)
        if @api_request
          halt 400, {:error => true, :message => text}.to_json
        else
          halt 400, message(text)
        end
      end
      
      def message(text)
        @message = text
        return erb :message
      end
      
      def oauth_dance(request, host)
        return_url = "#{protocol}://#{request.host_with_port}/oauth_success"
        redirect to("#{protocol}://#{host}/login/oauth2/auth?client_id=#{oauth_config.value}&response_type=code&redirect_uri=#{CGI.escape(return_url)}")
      end 
  
    end
  end
  
  register Views
end
