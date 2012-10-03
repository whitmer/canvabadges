require 'sinatra/base'

module Sinatra
  module BadgeData
    head "/badges/:course_id/:user_id/:code.json" do
      badge_data(params)
    end
    
    def badge_data(params)
      badge = Badge.first(:course_id => params[:course_id], :user_id => params[:user_id], :nonce => params[:code])
      headers 'Content-Type' => 'application/json'
      badge.badge_url = "https://#{request.host_with_port}" + badge.badge_url if badge.badge_url.match(/^\//)
      if badge
        return {
          :recipient => badge.recipient,
          :salt => badge.salt, 
          :issued_on => badge.issued.strftime("%Y-%m-%d"),
          :badge => {
            :version => "0.5.0",
            :name => badge.name,
            :image => badge.badge_url,
            :description => badge.description,
            :criteria => "/badges/#{badge.id}/criteria",
            :issuer => {
              :origin => "https://#{request.host_with_port}",
              :name => "Canvabadges",
              :org => "Instructure, Inc.",
              :contact => "support@instructure.com"
            }
          }
        }.to_json
      else
        return "Not Found"
      end
    end
    
    # badge details permalink
    get "/badges/:course_id/:user_id/:code.json" do
      badge_data(params)
    end
  end
  
  register BadgeData
end    
