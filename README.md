Badges
---------------------------
This is an LTI-enabled service that allows you to award badges
(Mozilla Open Badges, specifically) to students in a course
based on their accomplishments in the course. Currently this
will will only work with Canvas.

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
#  store your twitter token settings
ExternalConfig.create(:config_type => 'twitter_for_login', :value => "<twitter consmyer key>", :shared_secret => "<twitter shared secret>")
#  store you Canvas token settings
ExternalConfig.create(:config_type => 'canvas_oauth', :value => "<canvas developer key id>", :shared_secret => "<canvas developer secret>")
exit

# now start up your server
shotgun
```

Note that in a production environment you'll also need to set the SESSION_KEY environment variable or you'll get errors on boot.