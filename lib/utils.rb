require 'canvas-api'

module CanvasAPI
  def self.api_call(path, user_config, all_pages=false)
    protocol = 'https'
    host = "#{protocol}://#{user_config.host}"
    canvas = Canvas::API.new(:host => host, :token => user_config.access_token)
    begin
      result = canvas.get(path)
      if result.is_a?(Array) && all_pages
        while result.more?
          result.next_page!
        end
      end
      return result
    rescue Canvas::ApiError => e
      return false
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

module Stats
  def self.general(org)
    res = {}
    if org
      res['issuers'] = ExternalConfig.all(:organization_id => org.id).count
      res['badge_configs'] = BadgeConfig.all(:configured => true, :organization_id => org.id).count
      res['badge_placement_configs'] = BadgePlacementConfig.all(BadgePlacementConfig.badge_config.organization_id => org.id).count
      res['badges'] = Badge.all(:state => 'awarded', Badge.badge_config.organization_id => org.id).count
      res['domains'] = Domain.count
      res['organizations'] = Organization.count
    else
      res['issuers'] = ExternalConfig.count
      res['badge_configs'] = BadgeConfig.all(:configured => true).count
      res['badge_placement_configs'] = BadgePlacementConfig.count
      res['badges'] = Badge.all(:state => 'awarded').count
      res['domains'] = Domain.count
      res['organizations'] = Organization.count
    end
    res
  end
  
  def self.badge_earnings(bc)
    weeks = Badge.all(:badge_config_id => bc.id, :state => 'awarded').group_by{|b| (b.issued.year * 100) + b.issued.cweek }.map{|wk, badges| [wk, badges.length] }
    hash = {}
    weeks = weeks.sort_by{|wk, cnt| wk }
    weeks.each{|wk, cnt| hash[wk] = cnt }
    if weeks.length > 0
      hash['start'] = weeks[0][0]
      hash['end'] = weeks[-1][0]
    end
    hash
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