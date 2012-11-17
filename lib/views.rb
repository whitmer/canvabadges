require 'sinatra/base'

module Sinatra
  module Views
    get "/" do
      html = header
      html += message("<img src='/badges/default.png'/> Canvabadges are cool")
      html += footer
      html
    end

    # public page that shows requirements for badge completion
    get "/badges/criteria/:course_nonce" do
      course_config = CourseConfig.first(:nonce => params['course_nonce'])
      if !course_config
        return "Badge not found"
      end
      settings = course_config && JSON.parse(course_config.settings || "{}")
      html = header
      html += badge_description(settings)
      badge = Badge.first(:nonce => params['user'])
      if params['user'] && badge && badge.course_nonce == params['course_nonce']
        html += "<p><img src='/check.gif'/> This user completed the requirements necessary to receive this badge</p>"
      end
      html += footer
      html
    end
    
    get "/badges/all/:domain_id/:user_id" do
      for_current_user = session['user_id'] == params['user_id'] && session['domain_id'] == params['domain_id']
      badges = Badge.all(:user_id => params['user_id'], :domain_id => params['domain_id'])
      badges = badges.select{|b| b.public } unless for_current_user
      domain = Domain.first(:id => params['domain_id'])
      user = UserConfig.first(:user_id => params['user_id'], :domain_id => params['domain_id'])
      html = header
      if for_current_user
        html += "<h2>Your Badges at #{domain.name}</h2>"
      elsif user && domain
        html += "<h2>Badges for #{user.name || 'User'} at #{domain.name}</h2>"
      end
      if badges.empty?
        if for_current_user
          return "No data available"
        else
          html += "<p>No Badges Earned</p>"
        end
      end
      html += "<table>"
      badges.each do |badge|
        html += "<tr>"
        badge_url = for_current_user ? "/badges/check/#{badge.course_id}/#{badge.user_id}" : "/badges/criteria/#{badge.course_nonce}?user=#{badge.nonce}"
        html += "<td style='padding: 0 5px;'><a href='#{badge_url}'><img src='#{badge.badge_url}' class='thumbnail' alt='badge image'/></a></td>"
        html += "<td style='padding: 0 5px;'>#{badge.name}"
        if for_current_user
          html += "<form class='form-inline' action='/badges/#{badge.nonce}' style='margin: 0 0 0 15px;'><label><input class='public_badge' #{'checked' if badge.public} type='checkbox'/> public</label></form>"
        end
        html += "</td>"
        html += "</tr>"
      end
      html += "</table>"
      if for_current_user && !badges.empty?
        url = "#{protocol}://#{request.host_with_port}/badges/all/#{params['domain_id']}/#{params['user_id']}"
        html += "<br/><form class='form-inline'><label>Share this Page: <input type='text' value='#{url}'/></label></form>"
      end
      html += footer
    end
    
    # the magic page, APIs it up to make sure the user has done what they need to,
    # shows the results and lets them add the badge if they're done
    get "/badges/check/:domain_id/:course_id/:user_id" do
      if params['user_id'] != session['user_id'] || !session["permission_for_#{params['course_id']}"]
        return error("Invalid tool load #{session.to_json}")
      end
      user_config = UserConfig.first(:user_id => params['user_id'], :domain_id => params['domain_id'])
      if user_config
        course_config = CourseConfig.first(:course_id => params['course_id'], :domain_id => params['domain_id'])
        settings = course_config && JSON.parse(course_config.settings || "{}")
        if course_config && settings && settings['badge_url'] && settings['min_percent']
          json = api_call("/api/v1/courses/#{params['course_id']}?include[]=total_scores", user_config)
          return unless json
          
          student = json['enrollments'].detect{|e| e['type'] == 'student' }
          student['computed_final_score'] ||= 0 if student
          html = header
          html += badge_description(settings)
          if student
            badge = Badge.first(:user_id => params['user_id'], :course_id => params['course_id'], :domain_id => params['domain_id'])
            if !badge && student['computed_final_score'] >= settings['min_percent']
              badge = Badge.new(:user_id => params['user_id'], :course_id => params['course_id'], :domain_id => params['domain_id'])
              badge.name = settings['badge_name']
              badge.email = session['email']
              badge.description = settings['badge_description']
              badge.badge_url = settings['badge_url']
              badge.issued = DateTime.now
              badge.save
            end
            if badge
              html += "<h3>You've earned this badge!</h3>"
              if !badge.manual_approval
                html += "To earn this badge you needed #{settings['min_percent']}%, and you have #{student['computed_final_score'].to_f}% in this course right now."
                html += "<div class='progress progress-success progress-striped progress-big'><div class='tick' style='left: " + (3 * settings['min_percent']).to_i.to_s + "px;'></div><div class='bar' style='width: " + student['computed_final_score'].to_i.to_s + "%;'></div></div>"
              end
              url = "#{protocol}://#{request.host_with_port}/badges/data/#{params['course_id']}/#{params['user_id']}/#{badge.nonce}.json"
              html += "<form class='form-inline' action='/badges/#{badge.nonce}'><label><input class='public_badge' #{'checked' if badge.public} type='checkbox'/> Let others see this badge</label><br/>"
              html += "<a class='btn btn-primary btn-large' href='/badges/all/#{params['domain_id']}/#{session['user_id']}'>See All Your Badges</a>"
              html += "&nbsp;<a class='btn' style='background: #4a4842;' id='redeem' href='#' rel='#{url}'><span class='icon-plus icon-white'></span><img src='/mozilla-backpack.png' alt='Add this badge to your Mozilla backpack'/></a>"
              html += "</form>"
            else
              html += "<h3>You haven't earn this badge yet</h3>"
              html += "To earn this badge you need #{settings['min_percent']}%, but you only have #{student['computed_final_score'].to_f}% in this course right now."
              html += "<div class='progress progress-danger progress-striped progress-big'><div class='tick' style='left: " + (3 * settings['min_percent']).to_i.to_s + "px;'></div><div class='bar' style='width: " + student['computed_final_score'].to_i.to_s + "%;'></div></div>"
              html += "<a class='btn btn-primary btn-large' href='/badges/all/#{params['domain_id']}/#{session['user_id']}'>See All Your Badges</a>"
            end
          else
            html += "<h3>You are not a student in this course, so you can't earn this badge</h3>"
          end
          if session["permission_for_#{params['course_id']}"] == 'edit'
            html += student_list_html(params['domain_id'], user_config, course_config)
            html += edit_course_html(params['domain_id'], params['course_id'], params['user_id'], course_config)
          end
          html += footer
          return html
        else
          if session["permission_for_#{params['course_id']}"] == 'edit'
            html = header
            html += student_list_html(params['domain_id'], user_config, course_config)
            html += edit_course_html(params['domain_id'], params['course_id'], params['user_id'], course_config)
            html += footer
            return html
          else
            return message("Your teacher hasn't set up this badge yet")
          end
        end
      else
        return error("Invalid user session")
      end
    end
    
    helpers do      
      def badge_description(settings)
        html = ""
        html += "<img src='" + settings['badge_url'] + "' style='float: left; margin-right: 20px;' class='thumbnail'/>"
        html += "<h2>#{settings['badge_name'] || "Unnamed Badge"}</h2>"
        html += "<p class='desc'>#{settings['badge_description']}</p><div style='clear: left; padding-bottom: 10px;'></div>"
        html
      end
          
      def student_list_html(domain_id, user_config, course_config)
        settings = JSON.parse((course_config && course_config.settings) || "{}")
        if settings['min_percent']
          html = <<-HTML
            <ul class='nav nav-pills' style='margin-bottom: 5px; margin-top: 25px;'>
              <li id='current_students'>
                <a href="#">Current Students</a>
              </li><li id='awarded_students'>
                <a href="#">Awarded Students</a>
              </li>
            </ul>
            <table id="badges" class="table table-bordered table-striped" style='margin: 0 0 15px 0;' data-course_id="#{course_config.course_id}" data-domain_id="#{domain_id}">
              <thead>
                <tr>
                  <th>Student</th>
                  <th>Earned</th>
                  <th>Issued</th>
              </thead>
              <tbody>
          HTML
          json = []
          json.each do |student|
            badge = badges.detect{|b| b.user_id.to_i == student['id'] }
            html += <<-HTML
              <tr>
                <td>#{student['name']} (#{student['id']})</td>
                <td style='width: 200px;'>
            HTML
            if badge && badge.manual_approval
              html += "<img src='/add.png' alt='manually awarded' title='manually awarded'/>"
            elsif badge
              html += "<img src='/check.gif' alt='earned' title='earned'/>"
            else
              html += <<-HTML
                <img src='/redx.png' alt='not earned' class='earn_badge' title='not earned. click to manually award'/>
                <form class='form form-inline' method='POST' action='/badges/award/#{domain_id}/#{course_config.course_id}/#{student['id']}' style='visibility: hidden; display: inline; margin-left: 10px;'>
                  <button class='btn btn-primary' type='submit'><span class='icon-check icon-white'></span> Award Badge</button>
                </form>
              HTML
            end
            html += <<-HTML
                <td>#{(badge && badge.issued.strftime('%b %e, %Y')) || "&nbsp;"}</td>
              </tr>
            HTML
          end
          html += "</tbody></table>"
          return html
        end
        return ""
      end
      
      def edit_course_html(domain_id, course_id, user_id, course_config)
        settings = JSON.parse((course_config && course_config.root_settings) || "{}")
        ref_code = JSON.parse((course_config && course_config.settings) || "{}")['reference_code']
        disabled = course_config && course_config.root_id
        html = <<-HTML
          <form class='well form-horizontal' style="margin-top: 15px;" method="post" action="/badges/settings/#{domain_id}/#{course_id}">
          <h2>Badge Settings</h2>
          <img src="#{ settings['badge_url'] || '/badges/default.png' }" style='float: left; margin-right: 10px;' class='thumbnail'/>
          <fieldset>
          <div class="control-group">
            <label class="control-label" for="badge_name">Badge name: </label>
            <div class="controls">
              <input type="text" #{"disabled='true'" if disabled} class="span2" placeholder="name" id="badge_name" name="badge_name" value="#{CGI.escapeHTML(settings['badge_name'] || "")}"/>
            </div>
          </div>
          <div class="control-group">
            <label class="control-label" for="badge_url">Badge icon: </label>
            <div class="controls">
              <input type="text" #{"disabled='true'" if disabled} class="span2" placeholder="http://" id="badge_url" name="badge_url" value="#{CGI.escapeHTML(settings['badge_url'] || "")}"/>
              must be 72x72 pixels
            </div>
          </div>
          <div class="control-group">
            <label class="control-label" for="badge_description">Badge description: </label>
            <div class="controls">
              <textarea #{"disabled='true'" if disabled} class='input-xlarge' rows='3' name='badge_description' id='badge_description'>#{CGI.escapeHTML(settings['badge_description'] || "")}</textarea>
            </div>
          </div>
          <div class="control-group">
            <label class="control-label" for="reference_code">Badge reference code: </label>
            <div class="controls">
              <input type="text" placeholder="set to assign" class="span5" id="reference_code" name="reference_code" value="#{CGI.escapeHTML(ref_code || "")}"/>
              <br/>
              Set this value to reuse an existing badge. Clear to unlink from an existing badge. Remember: linking and unlinking will cause problems if any users have already exported badges.
        HTML
        if course_config
          html += <<-HTML
              To use this badge's settings for a different course, the code is #{course_config.reference_code}. 
          HTML
        end
        html += <<-HTML
            </div>
          </div>
          <div class="control-group">
            <label class="control-label" for="min_percent">Final grade cutoff: </label>
            <div class="controls">
              <div class="input-append">
                <input #{"disabled='true'" if disabled} type="text" class="span1" placeholder="##" id="min_percent" name="min_percent" value="#{settings['min_percent']}"/><span class='add-on'> % </span>
              </div>
            </div>
          </div>
          <div class="form-actions" style="border: 0; background: transparent;">
            <button type="submit" class='btn btn-primary'>Save Badge Settings</button>
          </div>
          </fieldset>
          </form> 
        HTML
      end
      
      def error(message)
        header + "<h2>" + message + "</h2>" + footer
      end
      
      def message(message)
        header + "<h2>" + message + "</h2>" + footer
      end
      
      def header
        <<-HTML
      <html>
        <head>
          <meta charset="utf-8">
          <title>Canvabadges</title>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <meta name="description" content="">
          <meta name="author" content="">
      
          <!-- Le styles -->
          <link href="/bootstrap/css/bootstrap.css" rel="stylesheet">
          <link href="/bootstrap/css/bootstrap-responsive.css" rel="stylesheet">
      
          <!-- Le HTML5 shim, for IE6-8 support of HTML5 elements -->
          <!--[if lt IE 9]>
            <script src="http://html5shim.googlecode.com/svn/trunk/html5.js"></script>
          <![endif]-->
      
          <!-- Le fav and touch icons -->
          <link rel="shortcut icon" href="/bootstrap/ico/favicon.ico">
          <link rel="apple-touch-icon-precomposed" sizes="114x114" href="/bootstrap/ico/apple-touch-icon-114-precomposed.png">
          <link rel="apple-touch-icon-precomposed" sizes="72x72" href="/bootstrap/ico/apple-touch-icon-72-precomposed.png">
          <link rel="apple-touch-icon-precomposed" href="/bootstrap/ico/apple-touch-icon-57-precomposed.png">
          <style>
          .progress-big, .progress-big .bar {
            height: 40px;
          }
          .progress-big {
            width: 300px;
            position: relative;
          }
          .progress-big .tick {
            z-index: 2;
            width: 0px;
            border: 1px solid #000;
            height: 44px;
            top: -2px;
            position: absolute;
          }
          body {
            padding-top: 40px;
          }
          .earn_badge {
            cursor: pointer;
          }
          .desc {
            white-space: pre-line;
          }
          </style>
        </head>
        <body>
          <div class="container" id="content">
          <div id="contents">
        HTML
      end
      
      def footer
        <<-HTML
          </div>
        </div>
        <script src="/jquery.min.js"></script>
        <script src="http://beta.openbadges.org/issuer.js"></script>
        <script src="/badges.js"></script>
      </body>
      </html>
        HTML
      end
      
    end
  end
  
  register Views
end
