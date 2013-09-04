Badges
---------------------------
This is an LTI-enabled service that allows you to award badges
(Mozilla Open Badges, specifically) to students in a course
based on their accomplishments in the course. Currently this
will will only work with Canvas. You can see (and use!) Canvabadges
at https://canvabadges.herokuapp.com.

Canvabadges now supports multiple badges per course, and has better
support for launching from multiple courses in the same session.

## Setup

You need two configurations set up in order to run this app.
First, you need to set up an application at dev.twitter.com. Write down your
key and secret. Next you'll need a developer key for the Canvas account
you want to speak with. Write down the key id and secret.

Below are instructions for starting up in a dev environment. If you know
how to run a production ruby environment you should be able to figure out
how to translate these instructions to your prod environment.

```bash
# install gems...
sudo bundle install

# let's set up the variables you'll need in order to function
irb
require './canvabadges.rb'
#  store your Canvas token settings
ExternalConfig.create(:config_type => 'canvas_oauth', :value => "<canvas developer key id>", :shared_secret => "<canvas developer secret>")
#  store your twitter token settings
ExternalConfig.create(:config_type => 'twitter_for_login', :value => "<twitter consmyer key>", :shared_secret => "<twitter shared secret>")
#  create a record matching your domain
#  set twitter_login to false if you only want LTI credentials created by hand
#  (twitter_login lets anyone generate an LTI key and secret with a twitter login)
d = Domain.create(:host => "badgemagic.yourdomain.com", :name => "Name Of Your Badging Thing")
o = Organization.create(:host => "badgemagic.yourdomain.com", :settings => {
  'name' => "Name Of Your Badging Thing", 
  'description' => "I just really like badging!",
  'twitter_login' => true,
  'url' => 'http://badgemagic.com',
  'image' => 'http://badgemagic.com/images/90x90.png',
  'email' => 'admin_or_support@badgemagic.com'
})
exit

# to create an LTI configuration by hand, do the following
irb
require './canvabadges.rb'
#  create a new LTI configuration
conf = ExternalConfig.generate("My Magic LTI Config")
#  print out the results
puts "key:    #{conf.value}"
puts "secret: #{conf.shared_secret}"
exit

# now start up your server
shotgun
```

Note that in a production environment you'll also need to set the SESSION_KEY environment variable or you'll get errors on boot.

[![Build Status](https://travis-ci.org/whitmer/canvabadges.png)](https://travis-ci.org/whitmer/canvabadges)