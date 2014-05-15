require 'sinatra/base'

module Sinatra
  module Views
    def self.registered(app)
      app.helpers Views::Helpers
      
      app.get "/" do
        @full_footer = true
        org_check
        @public_badge_placements = BadgePlacementConfig.all(:organization_id => @org.id, BadgePlacementConfig.badge_config.uncool => nil, BadgePlacementConfig.badge_config.public => true, :public_course => true, :order => :id.desc, :limit => 25)
        @public_badge_placements = @public_badge_placements.uniq{|p| [p.course_id, p.badge_config_id] }
        if @org.old_host && request.env['badges.original_domain'] == @org.old_host
          redirect to("#{protocol}://#{@org.host}/")
          return
        end
        
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
        @stats_org = @org
        @stats_org = nil if @org.default? && !params['this_org_only']
        @stats = Stats.general(@stats_org)
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
        org_check
        @badge_config = BadgeConfig.first(:id => params['id'], :nonce => params['nonce'])
        if !@badge_config
          return error("Badge not found")
        end
        @badge = Badge.first(:nonce => params['user'])
        if @badge
          @user_config = UserConfig.first(:user_id => @badge.user_id, :domain_id => @badge.domain_id)
          # TODO: Canvas needs a reliable way to get global user ids
          #@user_config ||= UserConfig.first(:global_user_id => @badge.global_user_id)
        end
        if !params['user']
          @stats = Stats.badge_earnings(@badge_config)
        end

        @earned = params['user'] && @badge && @badge.awarded? && @badge.config_nonce == params['nonce']
        erb :badge_completion
      end
      
      # show all public badges for the specified user
      app.get "/badges/all/:domain_id/:user_id" do
        org_check
        @for_current_user = session['user_id'] == params['user_id'] && session['domain_id'] == params['domain_id']
        @badges = Badge.all(:user_id => params['user_id'], :domain_id => params['domain_id'], :state => 'awarded')
        @badges = @badges.select{|b| b.public } unless @for_current_user
        @domain = Domain.first(:id => params['domain_id'])
        @user = UserConfig.first(:user_id => params['user_id'], :domain_id => params['domain_id'])
        erb :user_badges
      end
      
      app.get "/badges/course/:course_id" do  
        get_org
        permission_check(params['course_id'], 'view')
        @badges = Badge.all(:state => 'awarded', :user_id => session['user_id'], :course_id => params['course_id'], :domain_id => session['domain_id'])
        @user = UserConfig.first(:user_id => session['user_id'], :domain_id => session['domain_id'])
        halt 400, error("No user information found") unless @user
        @badge_placements = BadgePlacementConfig.all(:course_id => params['course_id'], :domain_id => session['domain_id'], :order => :id.desc).select(&:configured?).uniq{|p| p.badge_config_id }
        @other_badge_placements = BadgeConfigOwner.all(:user_config_id => @user.id, BadgeConfigOwner.badge_placement_config.course_id.not => params['course_id']).map(&:badge_placement_config).select(&:configured?)
        erb :course_badges
      end
      
      app.get "/badges/add_to_course/:badge_placement_id/:course_id" do
        org_check
        load_badge_config(params['badge_placement_id'], 'edit')
        permission_check(params['course_id'], 'edit')
        if @badge_placement_config.course_id == params['course_id']
          @bp = @badge_placement_config
        else
          id = "#{params['course_id']}-#{session['domain_id']}"
          @bp = BadgePlacementConfig.first_or_new(:course_id => params['course_id'], :domain_id => session['domain_id'], :placement_id => id)
          @bp.badge_config_id = @badge_placement_config.badge_config_id
          @bp.external_config_id = @badge_placement_config.external_config_id
          @bp.organization_id = @badge_placement_config.organization_id
          @bp.load_from_old_config(@user_config, @badge_placement_config)
          @bp.settings['award_only'] = true
          @bp.save
        end
        redirect to("#{request.env['badges.path_prefix']}/badges/check/#{@bp.id}/#{session['user_id']}")
      end
      
      # the magic page, APIs it up to make sure the user has done what they need to,
      # shows the results and lets them add the badge if they're done
      app.get "/badges/check/:badge_placement_config_id/:user_id" do
        org_check
        load_badge_config(params['badge_placement_config_id'], 'view')
        
        if @user_config && session["permission_for_#{@course_id}"] == 'edit'
          @badge_placement_config.teacher_user_config_id = @user_config.id
          @badge_placement_config.save
        end
        if @badge_placement_config && (@badge_placement_config.pending? || @badge_placement_config.needs_old_config_load?)
          @badge_placement_config.load_from_old_config(@user_config)
        end
        
        if @badge_placement_config && @badge_placement_config.configured?
          @student = {}
          erb :badge_check
        else
          if session["permission_for_#{@course_id}"] == 'edit'
            if @badge_placement_config.award_only?
              erb :badge_check
            else
              erb :manage_badge
            end
          else
            return message("Your teacher hasn't set up this badge yet")
          end
        end
      end

      app.get "/badges/modules/:badge_placement_config_id/:user_id" do
        org_check
        load_badge_config(params['badge_placement_config_id'], 'edit')
        @modules_json ||= CanvasAPI.api_call("/api/v1/courses/#{@course_id}/modules", @user_config, true)
        if @badge_placement_config.credit_based?
          @modules_json.each do |mod|
            
          end
        end
        erb :_badge_modules, :layout => false
      end
      
      app.get "/badges/outcomes/:badge_placement_config_id/:user_id" do
        org_check
        load_badge_config(params['badge_placement_config_id'], 'edit')
        @outcomes_json ||= CanvasAPI.api_call("/api/v1/courses/#{@course_id}/outcome_group_links", @user_config, true)
        erb :_badge_outcomes, :layout => false
      end
      
      app.get "/badges/status/:badge_placement_config_id/:user_id" do
        org_check
        load_badge_config(params['badge_placement_config_id'], 'view')
        if @badge_placement_config && @badge_placement_config.configured?
          if @badge && !@badge.needing_evaluation?
            @student = {}
          else
            begin
              args = @user_config.check_badge_status(@badge_placement_config, params, session['name'], session['email'])
            rescue => e
              puts e.message
              puts e.backtrace
              return "<h3>#{e.message}</h3>"
            end
            @student = args[:student]
            @completed_module_ids = args[:completed_module_ids]
            @completed_outcome_ids = args[:completed_outcome_ids]
            @badge = args[:badge]
          end
          if @student
            erb :_badge_status, :layout => false
          else
            return "<h3>You are not a student in this course, so you can't earn this badge</h3>"
          end
        elsif @badge_placement_config && @badge_placement_config.award_only?
          return ""
        else
          return "<h3>Error retrieving badge status</h3>"
        end
      end
    end
    
    
    module Helpers
      def org_check
        @org = Organization.first(:host => request.env['badges.original_domain'], :order => :id)
        @org ||= Organization.first(:old_host => request.env['badges.original_domain'], :order => :id)
        halt 404, error("Domain not properly configured. No Organization record matching the host #{request.env['badges.domain']}") unless @org
        CanvasAPI.set_org(@org)
      end
      
      def edit_course_html
        raise "no user" unless @user_config
        raise "missing value" unless @domain_id && @badge_placement_config_id && @course_id && @badge_placement_config_id
        erb :_badge_settings
      end
      
      def comma(number)
        number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end
      
      def error(text)
        if @api_request
          halt 400, {:error => true, :message => text}.to_json
        elsif text == "Session information lost" 
          halt 400, erb(:session_lost)
        else
          halt 400, message(text)
        end
      end
      
      def message(text)
        @message = text
        return erb :message
      end
      
      def oauth_dance(request, host)
        return_url = "#{protocol}://#{request.env['badges.original_domain']}/oauth_success"
        redirect to("#{protocol}://#{host}/login/oauth2/auth?client_id=#{oauth_config.value}&response_type=code&redirect_uri=#{CGI.escape(return_url)}")
      end 
  
    end
  end
  
  register Views
end
