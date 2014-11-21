require 'sinatra/base'

module Sinatra
  module Token
    def self.registered(app)
      app.helpers Token::Helpers
      
      app.get "/token" do
        org_check
        token_check
        erb :config_tokens
      end
      
      app.post "/token/connect" do
        token_check
        success = @conf.connect_to_organization(params['code'])
        if success
          api_response({:connect => true})
        else
          halt 400, api_response({error: "invalid code"})
        end
      end
      
      app.post "/token/disconnect" do
        token_check
        success = @conf.disconnect_from_organization
        api_response({:disconnect => true})
      end

      app.post "/token/organization" do
        token_check
        success = Organization.process(@conf, params)
        if success
          api_response({:update => true})
        else
          halt 400, api_response({error: "not authorized"})
        end
      end
    end
    
    
    module Helpers
      def token_redirect
        redirect to("/token?id=#{@conf.id}&confirmation=#{@conf.confirmation}")
      end
      
      def token_check
        @conf = ExternalConfig.first(:config_type => 'lti', :id => params['id'])
        @conf = nil if @conf && (!params['confirmation'] || @conf.confirmation != params['confirmation'])
        if !@conf
          halt 404, api_response({:error => "invalid token"})
        end
      end
    end
  end
  
  register Token
end
