$("#redeem").click(function(event) {
  event.preventDefault();
  OpenBadges.issue([$(this).attr('rel')]);
});
$(".public_badge").change(function() {
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
$("#evidence_url").change(function() {
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

$("input.credits").change(function() {
  var total = 0;
  $("input.credits").each(function() {
    total = total + (parseFloat($(this).val()) || 0);
  });
  $(".total_credits").text(total);
}).filter(":first").change();
$("#require_evidence").change(function() {
  if($(this).attr('checked')) {
    $("#manual_approval").attr('checked', true).attr('disabled', true);
  } else {
    $("#manual_approval").attr('disabled', false);
  }
}).change();
$("#credit_based").change(function() {
  $(".credits").toggle($(this).attr('checked'));
  $("input.credits").change();
}).change();

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
function loadResults(url) {
  $("#badges tbody").append("<tr class='loading'><td colspan='3'>Loading...</td></tr>");
  $.ajax({
    type: 'GET',
    dataType: 'json',
    url: url,
    success: function(data) {
      $("#badges tbody .loading").remove();
      var badge_config_id = $("#badges").attr('data-badge_config_id');
      for(var idx in data['objects']) {
        var badge = data['objects'][idx];
        badge.awarded = badge.issued && badge.state == 'awarded';
        badge.manually_awarded = badge.awarded && badge.manual;
        badge.pending = badge.state == 'pending';
        badge.badge_config_id = badge_config_id;
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
  var badge_config_id = $("#badges").attr('data-badge_config_id');
  if($(this).attr('id') == 'current_students') {
    loadResults("/api/v1/badges/current/" + badge_config_id + ".json");          
  } else {
    loadResults("/api/v1/badges/awarded/" + badge_config_id + ".json");          
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
