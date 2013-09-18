require 'sinatra/base'

module Sinatra
  module Views
    def self.registered(app)
      app.helpers Views::Helpers
      
      app.get "/" do
        @full_footer = true
        org_check
        erb (@org.settings['template'] || :index).to_sym
      end
      
      app.get "/about" do
        @full_footer = true
        org_check
        erb :about
      end
      
      app.get "/stats" do
        @full_footer = true
        org_check
        erb :stats
      end
      
      app.get "/badges/public" do
        @full_footer = true
        org_check
        if @org.default? && params['this_org_only']
          @badge_configs = BadgeConfig.all(:public => true, :order => :updated_at.desc, :limit => 25)
        else
          @badge_configs = BadgeConfig.all(:public => true, :order => :updated_at.desc, :limit => 25, :organization_id => @org.id)
        end
        erb :public_badge_configs
      end
      
      app.get "/badges/public/awarded" do
        @full_footer = true
        org_check
        if @org.default? && !params['this_org_only']
          @badges = Badge.all(:state => 'awarded', :public => true, :order => :issued.desc, :limit => 25)
        else
          @badges = Badge.all(Badge.badge_config.organization_id => @org.id, :state => 'awarded', :public => true, :order => :issued.desc, :limit => 25)
        end
        erb :public_badges
      end
      
      app.get "/canvabadges.xml" do
        response.headers['Content-Type'] = "text/xml"
        erb :config_xml, :layout => false
      end
  
      # public page that shows requirements for badge completion
      app.get "/badges/criteria/:id/:nonce" do
        @badge_config = BadgeConfig.first(:id => params['id'], :nonce => params['nonce'])
        if !@badge_config
          return error("Badge not found")
        end
        @badge = Badge.first(:nonce => params['user'])
        if @badge
          @user_config = UserConfig.first(:user_id => @badge.user_id, :domain_id => @badge.domain_id)
          @user_config ||= UserConfig.first(:global_user_id => @badge.global_user_id)
        end

        @earned = params['user'] && @badge && @badge.awarded? && @badge.config_nonce == params['nonce']
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
      app.get "/badges/check/:badge_config_id/:user_id" do
        load_badge_config(params['badge_config_id'], 'view')
        
        if @user_config && session["permission_for_#{@course_id}"] == 'edit'
          @badge_config.teacher_user_config_id = @user_config.id
          @badge_config.save
        end
        if @badge_config && @badge_config.pending?
          @badge_config.load_from_old_config(@user_config)
        end
        
        if @badge_config && @badge_config.configured?
          @student = {}
          erb :badge_check
        else
          if session["permission_for_#{@course_id}"] == 'edit'
            erb :manage_badge
          else
            return message("Your teacher hasn't set up this badge yet")
          end
        end
      end

      app.get "/badges/status/:badge_config_id/:user_id" do
        load_badge_config(params['badge_config_id'], 'view')
        if @badge_config && @badge_config.configured?
          if @badge && !@badge.needing_evaluation?
            @student = {}
          else
            begin
              args = @user_config.check_badge_status(@badge_config, params, session['name'], session['email'])
            rescue => e
              return "<h3>#{e.message}</h3>"
            end
            @student = args[:student]
            @completed_module_ids = args[:completed_module_ids]
            @badge = args[:badge]
          end
          if @student
            erb :_badge_status, :layout => false
          else
            return "<h3>You are not a student in this course, so you can't earn this badge</h3>"
          end
        else
          return "<h3>Error retrieving badge status</h3>"
        end
      end
    end
    
    
    module Helpers
      def org_check
        @org = Organization.first(:host => request.env['HTTP_HOST'])
        halt 404, error("Domain not properly configured. No Organization record matching the host #{request.env['HTTP_HOST']}") unless @org
      end
      
      def edit_course_html
        raise "no user" unless @user_config
        raise "missing value" unless @domain_id && @badge_config_id && @course_id && @badge_config
        @modules_json ||= CanvasAPI.api_call("/api/v1/courses/#{@course_id}/modules", @user_config)
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
