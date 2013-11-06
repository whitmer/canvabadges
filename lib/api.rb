require 'sinatra/base'

module Sinatra
  module Api
    def self.registered(app)
      app.helpers Api::Helpers
      
      # open badge organizations permalink
      # OBI-Compliant Result Required
      app.get "/api/v1/organizations/:id.json" do
        get_org
        org_id = params['id'].split(/-/)[0]
        if org_id == 'default'
          return api_response(Organization.new(:host => request.host_with_port).as_json)
        end
        config = Organization.first(:id => org_id)
        halt 404, api_response({:error => "not found"}) unless config && config.settings
        api_response(config.as_json)
      end
      
      # open badge details permalink
      # OBI-Compliant Result Required
      app.get "/api/v1/badges/summary/:id/:nonce.json" do
        get_org
        bc = BadgeConfig.first(:id => params['id'], :nonce => params['nonce'])
        bc = nil if bc && bc.organization_id != @org.id
        halt 404, api_response({:error => "not found"}) unless bc
        api_response(bc.as_json(@org.host))
      end
      
      # open badge organizations revocations permalink
      # OBI-Compliant Result Required
      app.get "/api/v1/organizations/:id/revocations.json" do
        get_org
        {}.to_json
      end

      # HEAD open badge award details permalink
      # OBI-Compliant Result Required
      app.head "/api/v1/badges/data/:badge_config_id/:user_id/:code.json" do
        get_org
        api_response(badge_data(params, @org.host))
      end

      # GET open badge award details permalink
      # OBI-Compliant Result Required
      app.get "/api/v1/badges/data/:badge_config_id/:user_id/:code.json" do
        get_org
        api_response(badge_data(params, @org.host))
      end

      # list of publicly available badges for the current user
      app.get "/api/v1/badges/public/:user_id/:host.json" do
        domain = Domain.first(:host => params['host'])
        return "bad domain: #{params['host']}" unless domain
        user = UserConfig.first(:domain_id => domain.id, :user_id => params['user_id'])
        badges_list = []
        if domain
          if user && user.global_user_id
            badges = Badge.all(:state => 'awarded', :global_user_id => user.global_user_id, :public => true)
          else
            badges = Badge.all(:state => 'awarded', :user_id => params['user_id'], :domain_id => domain.id, :public => true)
          end
          badges.each do |badge|
            badges_list << badge_hash(badge.user_id, badge.user_name, badge)
          end
        end
        result = {
          :objects => badges_list
        }
        api_response(result)
      end
      
      # list of students who have been awarded this badge, whether or not
      # they are currently active in the course
      # requires admin permissions
      app.get "/api/v1/badges/awarded/:badge_placement_config_id.json" do
        api_response(badge_list(true, params, session))
      end
      
      # list of students currently active in the course, showing whether
      # or not they have been awarded the badge
      # requires admin permissions
      app.get "/api/v1/badges/current/:badge_placement_config_id.json" do
        api_response(badge_list(false, params, session))
      end
      
      app.get "/badges/from_:type/:id/:nonce/badge.png" do
        url = nil
        if params['type'] == 'config'
          bc = BadgeConfig.first(:id => params['id'], :nonce => params['nonce'])
          url = bc && bc.settings && bc.settings['badge_url']
        elsif params['type'] == 'badge'
          b = Badge.first(:id => params['id'], :nonce => params['nonce'])
          url = b && b.badge_url
        end
        if url && url.match(/^data/)
          str = url.sub(/^data:image\/png;base64,/, '')
          content_type "image/png"
          Base64.strict_decode64(str)
        else
          "Badge image not found"
        end
      end
    end
    
    module Helpers
      def get_org
        @org = Organization.first(:host => request.env['HTTP_HOST'])
        halt(400, {:error => "Domain not properly configured. No Organization record matching the host #{request.env['HTTP_HOST']}"}.to_json) unless @org
      end
      
      def api_response(hash)
        if params['callback'] 
          "#{params['callback']}(#{hash.to_json});"
        else
          hash.to_json
        end
      end 
          
      def badge_data(params, host_with_port)
        bc = BadgeConfig.first(:id => params[:badge_config_id])
        badge = Badge.first(:state => 'awarded', :badge_config_id => params[:badge_config_id], :user_id => params[:user_id], :nonce => params[:code])
        badge = nil if bc && bc.organization_id != @org.id
        headers 'Content-Type' => 'application/json'
        if badge
          badge.badge_url = "#{protocol}://#{host_with_port}" + badge.badge_url if badge.badge_url.match(/^\//)
          return badge.open_badge_json(host_with_port)
        else
          halt 404, api_response({:error => "Not found"})
        end
      end
      
      def badge_list(awarded, params, session)
        @api_request = true
        load_badge_config(params['badge_placement_config_id'], 'edit')

        badges = Badge.all(:badge_config_id => @badge_placement_config.badge_config_id, :course_id => @course_id)
        result = []
        next_url = nil
        params['page'] = '1' if params['page'].to_i == 0
        if awarded
          badges = badges.all(:state => 'awarded')
          if badges.length > (params['page'].to_i * 50)
            next_url = "/api/v1/badges/awarded/#{@badge_placement_config_id}.json?page=#{params['page'].to_i + 1}"
          end
          badges = badges[((params['page'].to_i - 1) * 50), 50]
          badges.each do |badge|
            result << badge_hash(badge.user_id, badge.user_name, badge, @badge_placement_config && @badge_placement_config.nonce)
          end
        else
          json = api_call("/api/v1/courses/#{@course_id}/users?enrollment_type=student&per_page=50&page=#{params['page'].to_i}", @user_config)
          json.each do |student|
            badge = badges.detect{|b| b.user_id.to_i == student['id'] }
            result << badge_hash(student['id'], student['name'], badge, @badge_placement_config && @badge_placement_config.nonce)
          end
          if json.more?
            next_url = "/api/v1/badges/current/#{@badge_placement_config_id}.json?page=#{params['page'].to_i + 1}"
          end
        end
        return {
          :meta => {:next => next_url},
          :objects => result
        }
      end
      def badge_hash(user_id, user_name, badge, nonce=nil)
        if badge
          abs_url = badge.badge_url || "/badges/default.png"
          abs_url = "#{protocol}://#{request.host_with_port}" + abs_url unless abs_url.match(/\:\/\//) || abs_url.match(/^data/)
          {
            :id => user_id,
            :name => user_name,
            :manual => badge.manual_approval,
            :public => badge.public,
            :image_url => abs_url,
            :issued => badge && badge.issued && badge.issued.strftime('%b %e, %Y'),
            :nonce => badge && badge.nonce,
            :state => badge.state,
            :evidence_url => badge.evidence_url,
            :config_id => badge.badge_config_id,
            :placement_config_id => badge.badge_placement_config_id,
            :config_nonce => nonce || badge.config_nonce
          }
        else
          {
            :id => user_id,
            :name => user_name,
            :manual => nil,
            :public => nil,
            :image_url => nil,
            :issued => nil,
            :nonce => nil,
            :state => 'unissued',
            :evidence_url => nil,
            :config_id => nil,
            :placement_config_id => nil,
            :config_nonce => nonce
          }
        end
      end

      def protocol
        ENV['RACK_ENV'].to_s == "development" ? "http" : "https"
      end
      
      def api_call(path, user_config, post_params=nil)
        res = CanvasAPI.api_call(path, user_config, post_params)
        if res == false
          oauth_dance(request, user_config.host)
        else
          res
        end
      end
      
      def oauth_config
        get_org
        @oauth_config = OAuthConfig.oauth_config(@org)
      end
    end
  end
  
  register Api
end
