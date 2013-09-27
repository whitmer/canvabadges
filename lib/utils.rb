module CanvasAPI
  def self.api_call(path, user_config, post_params=nil)
    protocol = 'https'
    url = "#{protocol}://#{user_config.host}" + path
    url += (url.match(/\?/) ? "&" : "?") + "access_token=#{user_config.access_token}"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = protocol == "https"
    req = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(req)
    json = JSON.parse(response.body)
    json.instance_variable_set('@has_more', (response['Link'] || '').match(/rel=\"next\"/))
    if response.code != "200"
      false
    else
      json
    end
  end
end

module OAuthConfig
  def self.oauth_config(org=nil)
    if org && org.settings['oss_oauth']
      oauth_config ||= ExternalConfig.first(:config_type => 'canvas_oss_oauth', :organization_id => org.id)
    else
      oauth_config ||= ExternalConfig.first(:config_type => 'canvas_oauth')
    end
    
    raise "Missing oauth config" unless oauth_config
    oauth_config
  end
end

require 'dm-migrations/migration_runner'
require 'dm-types'
# I can never find good documentation on migrations for datamapper, don't judge
module  FixupMigration
  def self.enlarge_columns
    migration 1, :enlarge_small_columns do
      up do
        # user config
        modify_table :user_configs do
          add_column :temp_access_token, String, :length => 512
        end
        adapter.execute("UPDATE user_configs SET temp_access_token=access_token")
        modify_table :user_configs do
          drop_column :access_token
          rename_column :temp_access_token, :access_token
        end

        # badges
        modify_table :badges do
          add_column :temp_badge_url, DataMapper::Property::Text
          add_column :temp_salt, String, :length => 512
        end
        adapter.execute("UPDATE badges SET temp_badge_url=badge_url, temp_salt=salt")
        modify_table :badges do
          drop_column :badge_url
          drop_column :salt
          rename_column :temp_badge_url, :badge_url
          rename_column :temp_salt, :salt
        end
      end
    end
    migrate_up!
  end
end