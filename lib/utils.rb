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