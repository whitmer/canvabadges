$(function() {
  // NOTE: if pasting this code into another script, you'll need to manually change the
  // next line. Instead of assigning the value null, you need to assign the value of
  // the Canvabadges domain, i.e. "https://canvabadges.herokuapp.com". If you have a custom
  // domain configured then it'll be something like "https://canvabadges.herokuapp.com/_my_site"
  // instead.
  var protocol_and_host = null;
  var $scripts = $("script");
  $("script").each(function() {
    var src = $(this).attr('src');
    if(src && src.match(/canvas_profile_badges/)) {
      var splits = src.split(/\//);
      protocol_and_host = splits[0] + "//" + splits[2];
    }
    var prefix = src && src.match(/\?path_prefix=\/(\w+)/);
    if(prefix && prefix[1]) {
      protocol_and_host = protocol_and_host + "/" + prefix[1];
    }
  });
  if(!protocol_and_host) {
    console.log("Couldn't find a valid protocol and host. Canvabadges will not appear on profile pages until this is fixed.");
  }
  var match = location.href.match(/\/(users|about)\/(\d+)$/);
  if(match && protocol_and_host) {
    var user_id = match[2];
    var domain = location.host;
    var url = protocol_and_host + "/api/v1/badges/public/" + user_id + "/" + encodeURIComponent(domain) + ".json";
    $.ajax({
      type: 'GET',
      dataType: 'jsonp',
      url: url,
      success: function(data) {
        if(data.objects && data.objects.length > 0) {
          var $box = $("<div/>");
          $box.append("<h2 class='border border-b'>Badges</h2>");
          for(idx in data.objects) {
            var badge = data.objects[idx];
            var $badge = $("<div/>", {style: 'float: left;'});
            var link = protocol_and_host + "/badges/criteria/" + badge.config_id + "/" + badge.config_nonce + "?user=" + badge.nonce;
            var $a = $("<a/>", {href: link});
            $a.append($("<img/>", {src: badge.image_url, style: 'width: 72px; height: 72px; padding-right: 10px;'}));
            $badge.append($a);
            $box.append($badge);
          }
          $box.append($("<div/>", {style: 'clear: left'}));
          $("#edit_profile_form,fieldset#courses,.more_user_information + div").after($box);
        }
      },
      error: function() {
        console.log("badges failed to load");
      },
      timeout: 5000
    });
  }
});