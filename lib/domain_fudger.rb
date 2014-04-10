class DomainFudger
  def initialize(app)
    @app = app
  end
  
  def call(env)
    original_env = env.merge({})
    scheme = env['rack.url_scheme']
    host = env['HTTP_HOST']
    path = env['PATH_INFO'] || ""
    domain = host
    env['badges.path_prefix'] = ""
    if path.match(/^\/_/)
      nothing, domain_piece, new_path = path.split(/\//, 3)
      new_path = new_path || ""
      domain += "/" + domain_piece
      env['PATH_INFO'] = "/" + new_path
      env['badges.path_prefix'] = "/" + domain_piece
      env['REQUEST_URI'] = scheme + "://" + host + "/" + new_path
      if env['QUERY_STRING'] && env['QUERY_STRING'].length > 0
        env['REQUEST_URI'] += "?" + env['QUERY_STRING']
      end
      env['REQUEST_PATH'] = "/" + new_path
    end
    env['badges.original_domain'] = domain
    env['badges.domain'] = domain.sub(/canvabadges\.herokuapp\.com/, 'www.canvabadges.org')
    env['badges.original_env'] = original_env
    @app.call(env)
  end
end