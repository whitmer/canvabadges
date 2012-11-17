require 'sinatra/base'

module Sinatra
  module Api
    # list of publicly available badges for the current user
    get "/api/v1/badges/public/:user_id/:host.json" do
      domain = Domain.first(:host => params['host'])
      badge_list = []
      return "bad domain: #{params['host']}" unless domain
      if domain
        badges = Badge.all(:user_id => params['user_id'], :domain_id => domain.id, :public => true)
        badges.each do |badge|
          badge_list << badge_hash(badge.user_id, badge.user_name, badge)
        end
      end
      result = {
        :objects => badge_list
      }
      api_response(result)
    end
    
    # list of students who have been awarded this badge, whether or not
    # they are currently active in the course
    # requires admin permissions
    get "/api/v1/badges/awarded/:domain_id/:course_id.json" do
      api_response(badge_list(true, params, session))
    end
    
    # list of students currently active in the course, showing whether
    # or not they have been awarded the badge
    # requires admin permissions
    get "/api/v1/badges/current/:domain_id/:course_id.json" do
      api_response(badge_list(false, params, session))
    end
    
    # open badge details permalink
    head "api/v1/badges/data/:course_id/:user_id/:code.json" do
      api_response(badge_data(params))
    end
    
    # open badge details permalink
    get "api/v1/badges/data/:course_id/:user_id/:code.json" do
      api_response(badge_data(params, request.host_with_port))
    end
    
    helpers do 
      def api_response(hash)
        if params['callback'] 
          "#{params['callback']}(#{hash.to_json});"
        else
          hash.to_json
        end
      end 
          
      def badge_data(params, host_with_port)
        badge = Badge.first(:course_id => params[:course_id], :user_id => params[:user_id], :nonce => params[:code])
        headers 'Content-Type' => 'application/json'
        badge.badge_url = "#{protocol}://#{host_with_port}" + badge.badge_url if badge.badge_url.match(/^\//)
        if badge
          return open_badge_json(badge)
        else
          return "Not Found"
        end
      end
      
      def open_badge_json(badge, host_with_port)
        {
          :recipient => badge.recipient,
          :salt => badge.salt, 
          :issued_on => badge.issued.strftime("%Y-%m-%d"),
          :badge => {
            :version => "0.5.0",
            :name => badge.name,
            :image => badge.badge_url,
            :description => badge.description,
            :criteria => "/badges/criteria/#{badge.course_nonce}",
            :issuer => {
              :origin => "#{protocol}://#{host_with_port}",
              :name => "Canvabadges",
              :org => "Instructure, Inc.",
              :contact => "support@instructure.com"
            }
          }
        }
      end
      
      def badge_list(awarded, params, session)
        user_config = UserConfig.first(:user_id => session['user_id'], :domain_id => params['domain_id'])
        course_config = CourseConfig.first(:course_id => params['course_id'], :domain_id => params['domain_id'])
        if !session["permission_for_#{params['course_id']}"] || !user_config
          return {:error => "Invalid permissions"}.to_json
        end
        badges = Badge.all(:domain_id => params['domain_id'], :course_id => params['course_id'])
        result = []
        next_url = nil
        params['page'] = '1' if params['page'].to_i == 0
        if awarded
          badges.each do |badge|
            result << badge_hash(badge.user_id, badge.user_name, badge, course_config && course_config.root_nonce)
          end
          badges = badges[params['page'].to_i, 50]
          if badges.length > params['page'].to_i * 50
            next_url = "/badges/awarded/#{params['domain_id']}/#{params['course_id']}.json?page=#{params['page'].to_i + 1}"
          end
        else
          json = api_call("/api/v1/courses/#{params['course_id']}/users?enrollment_type=student&per_page=50&page=#{params['page'].to_i}", user_config)
          json.each do |student|
            badge = badges.detect{|b| b.user_id.to_i == student['id'] }
            result << badge_hash(student['id'], student['name'], badge, course_config && course_config.root_nonce)
          end
          if json.instance_variable_get('@has_more')
            next_url = "/badges/current/#{params['domain_id']}/#{params['course_id']}.json?page=#{params['page'].to_i + 1}"
          end
        end
        return {
          :meta => {:next => next_url},
          :objects => result
        }
      end
      def badge_hash(user_id, user_name, badge, root_nonce=nil)
        abs_url = badge.badge_url || "/badges/default.png"
        abs_url = "#{protocol}://#{request.host_with_port}" + abs_url unless abs_url.match(/\:\/\//)
        {
          :id => user_id,
          :name => user_name,
          :manual => badge.manual_approval,
          :public => badge.public,
          :image_url => abs_url,
          :issued => badge && badge.issued.strftime('%b %e, %Y'),
          :nonce => badge && badge.nonce,
          :course_nonce => root_nonce || badge.course_nonce
        }
      end
    end
  end
  
  register Api
end
