require 'sinatra/base'

module Sinatra
  module Config
    def config_wrap(xml)
      res = <<-XML
    <?xml version="1.0" encoding="UTF-8"?>
      <cartridge_basiclti_link xmlns="http://www.imsglobal.org/xsd/imslticc_v1p0"
          xmlns:blti = "http://www.imsglobal.org/xsd/imsbasiclti_v1p0"
          xmlns:lticm ="http://www.imsglobal.org/xsd/imslticm_v1p0"
          xmlns:lticp ="http://www.imsglobal.org/xsd/imslticp_v1p0"
          xmlns:xsi = "http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation = "http://www.imsglobal.org/xsd/imslticc_v1p0 http://www.imsglobal.org/xsd/lti/ltiv1p0/imslticc_v1p0.xsd
          http://www.imsglobal.org/xsd/imsbasiclti_v1p0 http://www.imsglobal.org/xsd/lti/ltiv1p0/imsbasiclti_v1p0.xsd
          http://www.imsglobal.org/xsd/imslticm_v1p0 http://www.imsglobal.org/xsd/lti/ltiv1p0/imslticm_v1p0.xsd
          http://www.imsglobal.org/xsd/imslticp_v1p0 http://www.imsglobal.org/xsd/lti/ltiv1p0/imslticp_v1p0.xsd">
      XML
      res += xml
      res += <<-XML
          <cartridge_bundle identifierref="BLTI001_Bundle"/>
          <cartridge_icon identifierref="BLTI001_Icon"/>
      </cartridge_basiclti_link>  
      XML
    end
    
    get "/config.xml" do
      host = "#{protocol}://" + request.host_with_port
      headers 'Content-Type' => 'text/xml'
      xml =  <<-XML
        <blti:title>Mozilla Open Badges</blti:title>
        <blti:description>Award open badges to students based on their course accomplishments</blti:description>
        <blti:launch_url>#{host}/badge_check</blti:launch_url>
        <blti:extensions platform="canvas.instructure.com">
          <lticm:property name="privacy_level">public</lticm:property>
      XML
      if params['course_nav']
        xml +=  <<-XML
          <lticm:options name="user_navigation">
            <lticm:property name="url">#{host}/badge_check</lticm:property>
            <lticm:property name="text">Badge</lticm:property>
          </lticm:options>
        XML
      end
      xml +=  <<-XML
        </blti:extensions>
      XML
      config_wrap(xml)
    end
    
  end
  
  register Config
end