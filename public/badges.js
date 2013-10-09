$(document).on('click', '#redeem', function(event) {
  event.preventDefault();
  OpenBadges.issue([$(this).attr('rel')]);
});
$(document).on('change', ".public_badge", function() {
  var url = $(this).closest("form").attr('action');
  $.ajax({
    type: 'POST',
    dataType: 'json',
    url: url,
    data: {
      public: ($(this).attr('checked') ? 'true' : 'false')
    },
    error: function() {
    }
  });
});
$(document).on('click', "#disable_badge", function() {
  var result = confirm("Are you sure you want to disable this badge? It may still appear to students if it is placed more than in time in the course.");
  if(!result) { return; }
  var url = $(this).attr('rel');
  $.ajax({
    type: 'POST',
    dataType: 'json',
    url: url,
    success: function() {
      location.reload();
    },
    error: function() {
      alert("Disable failed. Please try again.");
    }
  });
});
$(document).on('change', "#evidence_url", function() {
  var url = $(this).closest("form").attr('rel');
  $.ajax({
    type: 'POST',
    dataType: 'json',
    url: url,
    data: {
      evidence_url: $(this).val()
    },
    error: function() {
    }
  });
});

$(document).on('change', "input.credits", function() {
  var total = 0;
  $("input.credits").each(function() {
    total = total + (parseFloat($(this).val()) || 0);
  });
  $(".total_credits").text(total);
})
$("input.credits:first").change();
$(document).on('change', "#require_evidence", function() {
  if($(this).attr('checked')) {
    $("#manual_approval").attr('checked', true).attr('disabled', true);
  } else {
    $("#manual_approval").attr('disabled', false);
  }
}).change();
$(document).on('change', "#credit_based", function() {
  $(".credits").toggle($(this).attr('checked'));
  $("input.credits").change();
})
$("#credit_based").change();

$(".earn_badge").live('click', function() {
  $(this).parent().find("form").css('visibility', 'visible');
});
$(".more").live('click', function(event) {
  event.preventDefault();
  $(this).remove();
  loadResults($(this).attr('rel'));
});
$('.evidence_link').live('click', function(event) {
  $(this).closest("tr").addClass('selected_row');
});
$("#show_other_badges").live('click', function(event) {
  $(this).hide();
  $("#other_badges").show();
});
function loadResults(url) {
  $("#badges tbody").append("<tr class='loading'><td colspan='3'>Loading...</td></tr>");
  $.ajax({
    type: 'GET',
    dataType: 'json',
    url: url,
    success: function(data) {
      $("#badges tbody .loading").remove();
      var badge_placement_config_id = $("#badges").attr('data-badge_placement_config_id');
      var badge_config_id = $("#badges").attr('data-badge_config_id');
      for(var idx in data['objects']) {
        var badge = data['objects'][idx];
        badge.awarded = badge.issued && badge.state == 'awarded';
        badge.manually_awarded = badge.awarded && badge.manual;
        badge.pending = badge.state == 'pending';
        badge.badge_config_id = badge_config_id;
        badge.badge_placement_config_id = badge_placement_config_id;
        $("#badges tbody").append(Handlebars.templates['badge_row'](badge));
      }
      if(data['meta']['next']) {
        $("#badges tbody").append("<tr class='more' rel='" + data['meta']['next'] + "'><td colspan='3'><a href='#'>more...</a></td></tr>");
      }
    },
    error: function() {
      $("#badges tbody .loading td").text("Loading Failed");
    }
  });
}
$(".nav-pills li").click(function(event) {
  event.preventDefault();
  $(".nav-pills li").removeClass('active');
  $(this).addClass('active');
  $("#badges tbody").empty();
  var badge_placement_config_id = $("#badges").attr('data-badge_placement_config_id');
  if($(this).attr('id') == 'current_students') {
    loadResults("/api/v1/badges/current/" + badge_placement_config_id + ".json");          
  } else {
    loadResults("/api/v1/badges/awarded/" + badge_placement_config_id + ".json");          
  }
});
$("#current_students").click();

var badge_status = $("#student_badge").attr('rel');
if(badge_status) {
  $.ajax({
    type: 'GET',
    dataType: 'html',
    url: badge_status,
    success: function(data) {
      $("#student_badge").html(data);
    },
    error: function(data) {
      $("#student_badge").html("<h3>Error retrieving badge status</h3>");
    }
  });
}

$(document).ready(function (){
  window.onmessage = function(e){
    if(e.origin=='https://www.openbadges.me'){
      if(e.data!='cancelled')
      $('#badge_url').val(e.data);
      $.fancybox.close();
    }
  };
  
  $("#badge_designer").fancybox({
    width		: '90%',
    height	: '70%',
    minHeight	: 600,
    autoSize	: false,
    closeClick	: false,
    openEffect	: 'fade',
    closeEffect	: 'none'
  });

});

$(document).on('click', '.select_badge_config', function(event) {
  event.preventDefault();

  var url = location.href;
  var args = (url.split(/#/)[0].split(/\?/)[1] || "").split(/\&/);
  var params = {};
  for(var idx in args) {
    var arg = args[idx].split(/\=/);
    var key = arg[0];
    var value = arg[1];
    if(key && value) {
      params[key] = decodeURIComponent(value);
    }
  }

  var host = location.origin || (location.protocol + "//" + location.host);
  var launch = host + "/placement_launch";
  var $config = $(this).closest(".badge_config");
  var badge_id = $config.attr('data-id') || $config.attr('data-proposed_id')
  var badge_name = ($config.find(".name").val() || $config.find('.name').text() || "New Badge");
  if(badge_id == 'list') {
    launch = launch + "?custom_show_course=1";
    badge_name = "All Badges";
  } else {
    launch = launch + "?badge_reuse_code=" + badge_id;
    if(!$config.attr('data-id')) {
      launch = launch + "&badge_name=" + encodeURIComponent(badge_name);
    }
    badge_name = "Badge: " + badge_name;
  }

  var return_url = params.return_url;
  return_url = return_url + (return_url.match(/\?/) ? "&" : "?");
  location.href = return_url + "return_type=lti_launch_url&url=" + encodeURIComponent(launch) + "&text=" + encodeURIComponent(badge_name) + "&title=" + encodeURIComponent(badge_name);
});
$(document).on('click', '#session_fixer', function(event) {
  window.open("/session_fix", "Session Fixer", "width=400,height=300,resizable=no,menubar=no,location=no,toolbar=no");
});
