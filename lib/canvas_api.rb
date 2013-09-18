module CanvasAPI
  def self.api_call(path, user_config, post_params=nil)
    protocol = 'https'
    url = "#{protocol}://#{user_config.host}" + path
    url += (url.match(/\?/) ? "&" : "?") + "access_token=#{user_config.access_token}"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    puts "API"
    puts url
    http.use_ssl = protocol == "https"
    req = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(req)
    json = JSON.parse(response.body)
    puts response.body
    json.instance_variable_set('@has_more', (response['Link'] || '').match(/rel=\"next\"/))
    if response.code != "200"
      puts "bad response"
      puts response.body
      oauth_dance(request, user_config.host)
      false
    else
      json
    end
  end
end