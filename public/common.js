window.path_prefix = $("body").attr('data-path_prefix') || "";

// lib/handlebars/base.js
var Handlebars = {};

Handlebars.VERSION = "1.0.beta.2";

Handlebars.helpers  = {};
Handlebars.partials = {};

Handlebars.registerHelper = function(name, fn, inverse) {
  if(inverse) { fn.not = inverse; }
  this.helpers[name] = fn;
};

Handlebars.registerPartial = function(name, str) {
  this.partials[name] = str;
};

Handlebars.registerHelper('helperMissing', function(arg) {
  if(arguments.length === 2) {
    return undefined;
  } else {
    throw new Error("Could not find property '" + arg + "'");
  }
});

Handlebars.registerHelper('blockHelperMissing', function(context, options) {
  var inverse = options.inverse || function() {}, fn = options.fn;


  var ret = "";
  var type = Object.prototype.toString.call(context);

  if(type === "[object Function]") {
    context = context();
  }

  if(context === true) {
    return fn(this);
  } else if(context === false || context == null) {
    return inverse(this);
  } else if(type === "[object Array]") {
    if(context.length > 0) {
      for(var i=0, j=context.length; i<j; i++) {
        ret = ret + fn(context[i]);
      }
    } else {
      ret = inverse(this);
    }
    return ret;
  } else {
    return fn(context);
  }
});

Handlebars.registerHelper('each', function(context, options) {
  var fn = options.fn, inverse = options.inverse;
  var ret = "";

  if(context && context.length > 0) {
    for(var i=0, j=context.length; i<j; i++) {
      ret = ret + fn(context[i]);
    }
  } else {
    ret = inverse(this);
  }
  return ret;
});

Handlebars.registerHelper('if', function(context, options) {
  if(!context || Handlebars.Utils.isEmpty(context)) {
    return options.inverse(this);
  } else {
    return options.fn(this);
  }
});

Handlebars.registerHelper('unless', function(context, options) {
  var fn = options.fn, inverse = options.inverse;
  options.fn = inverse;
  options.inverse = fn;

  return Handlebars.helpers['if'].call(this, context, options);
});

Handlebars.registerHelper('with', function(context, options) {
  return options.fn(context);
});
;
// lib/handlebars/utils.js
Handlebars.Exception = function(message) {
  var tmp = Error.prototype.constructor.apply(this, arguments);

  for (var p in tmp) {
    if (tmp.hasOwnProperty(p)) { this[p] = tmp[p]; }
  }
};
Handlebars.Exception.prototype = new Error;

// Build out our basic SafeString type
Handlebars.SafeString = function(string) {
  this.string = string;
};
Handlebars.SafeString.prototype.toString = function() {
  return this.string.toString();
};

(function() {
  var escape = {
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#x27;",
    "`": "&#x60;"
  };

  var badChars = /&(?!\w+;)|[<>"'`]/g;
  var possible = /[&<>"'`]/;

  var escapeChar = function(chr) {
    return escape[chr] || "&amp;";
  };

  Handlebars.Utils = {
    escapeExpression: function(string) {
      // don't escape SafeStrings, since they're already safe
      if (string instanceof Handlebars.SafeString) {
        return string.toString();
      } else if (string == null || string === false) {
        return "";
      }

      if(!possible.test(string)) { return string; }
      return string.replace(badChars, escapeChar);
    },

    isEmpty: function(value) {
      if (typeof value === "undefined") {
        return true;
      } else if (value === null) {
        return true;
      } else if (value === false) {
        return true;
      } else if(Object.prototype.toString.call(value) === "[object Array]" && value.length === 0) {
        return true;
      } else {
        return false;
      }
    }
  };
})();;
// lib/handlebars/vm.js
Handlebars.VM = {
  template: function(templateSpec) {
    // Just add water
    var container = {
      escapeExpression: Handlebars.Utils.escapeExpression,
      invokePartial: Handlebars.VM.invokePartial,
      programs: [],
      program: function(i, fn, data) {
        var programWrapper = this.programs[i];
        if(data) {
          return Handlebars.VM.program(fn, data);
        } else if(programWrapper) {
          return programWrapper;
        } else {
          programWrapper = this.programs[i] = Handlebars.VM.program(fn);
          return programWrapper;
        }
      },
      programWithDepth: Handlebars.VM.programWithDepth,
      noop: Handlebars.VM.noop
    };

    return function(context, options) {
      options = options || {};
      return templateSpec.call(container, Handlebars, context, options.helpers, options.partials, options.data);
    };
  },

  programWithDepth: function(fn, data, $depth) {
    var args = Array.prototype.slice.call(arguments, 2);

    return function(context, options) {
      options = options || {};

      return fn.apply(this, [context, options.data || data].concat(args));
    };
  },
  program: function(fn, data) {
    return function(context, options) {
      options = options || {};

      return fn(context, options.data || data);
    };
  },
  noop: function() { return ""; },
  invokePartial: function(partial, name, context, helpers, partials) {
    if(partial === undefined) {
      throw new Handlebars.Exception("The partial " + name + " could not be found");
    } else if(partial instanceof Function) {
      return partial(context, {helpers: helpers, partials: partials});
    } else if (!Handlebars.compile) {
      throw new Handlebars.Exception("The partial " + name + " could not be compiled when running in vm mode");
    } else {
      partials[name] = Handlebars.compile(partial);
      return partials[name](context, {helpers: helpers, partials: partials});
    }
  }
};

Handlebars.template = Handlebars.VM.template;

(function() {
  var extensions_hash = {
    'editor_button': 'editor',
    'resource_selection': 'resources',
    'course_nav': 'course nav',
    'user_nav': 'profile nav',
    'account_nav': 'account nav',
    'homework_submission': 'homework'
  }
  var index = 0;
  Handlebars.registerHelper('checked_if_included', function(context, options) {
    return (options.hash['val'] || []).indexOf(context) == -1 ? "" : "checked";
  });
  Handlebars.registerHelper('array_as_string', function(context, options) {
    return (context || []).join(",");
  });
  Handlebars.registerHelper('each_in_hash', function(context, options) {
    var new_context = [];
    for(var idx in context) {
      new_context.push({
        key: idx,
        value: context[idx]
      });
    }
    context = new_context;
    var fn = options.fn, inverse = options.inverse;
    var ret = "";
  
    if(context && context.length > 0) {
      for(var i=0, j=context.length; i<j; i++) {
        ret = ret + fn(context[i]);
      }
    } else {
      ret = inverse(this);
    }
    return ret;
  });
  Handlebars.registerHelper('increment_index', function() {
    index++;
    return "";
  });
  Handlebars.registerHelper('current_index', function() {
    return index;
  });
  Handlebars.registerHelper('extensions_list', function(context, options) {
    var res = "";
    context = context || [];
    for(var idx = 0; idx < context.length; idx++) {
      if(extensions_hash[context[idx]]) {
        res = res + "<span class='label'>" + extensions_hash[context[idx]] + "</span>&nbsp;";
      }
    }
    return new Handlebars.SafeString(res);
  });
  Handlebars.registerHelper('round', function(context, options) {
    return Math.round(context * 10.0) / 10.0;
  });
  Handlebars.registerHelper('if_eql', function(context, options) {
    if(context == options.hash['val']) {
      return options.fn(this);
    } else {
      return options.inverse(this);
    }
  });
  Handlebars.registerHelper('if_string', function(context, options) {
    if(typeof(context) == 'string') {
      return options.fn(this);
    } else {
      return options.inverse(this);
    }
  });
  Handlebars.registerHelper('full_url', function(context, options) {
    if(!context.match(/\/\//)) {
      context = location.protocol + "//" + location.host + context;
    }
    return context;
  });
  Handlebars.registerHelper('stars', function(context, options) {
    context = Math.round(context * 2.0) / 2.0;
    var context_str = context.toString().replace(/\./, '_');
    var title = "No Ratings";
    if(context) {
      title = context + " Star" + (context == 1 ? "" : "s");
    }
    var res = "<span title='" + title + "' class='stars star" + context_str + "'>";
    for(var idx = 0; idx < 5; idx++) {
      res = res + "<img data-star='" + (idx + 1) + "' class='star star" + (idx + 1) + "' src='/blank.png'/> ";
    }
    res = res + "</span>";
    return new Handlebars.SafeString(res);
  });
  Handlebars.registerHelper('small_stars', function(context, options) {
    context = Math.round(context);
    var res = "<span title='" + context + " star" + (context == 1 ? "" : "s") + "' style='line-height: 10px;'>";
    for(var idx = 0; idx < 5; idx++) {
      res = res + "<img style='width: 10px; height: 10px;' class='star" + (idx + 1) + "' src='/star" + (context > idx ? "" : "_empty") + ".png'/> ";
    }
    res = res + "</span>";
    return new Handlebars.SafeString(res);
  });
})();
// Handlebars templates
(function() {
  var template = Handlebars.template, templates = Handlebars.templates = Handlebars.templates || {};
templates['badge_row'] = template(function (Handlebars,depth0,helpers,partials,data) {
  helpers = helpers || Handlebars.helpers;
  var buffer = "", stack1, stack2, foundHelper, tmp1, self=this, functionType="function", helperMissing=helpers.helperMissing, undef=void 0, escapeExpression=this.escapeExpression;

function program1(depth0,data) {
  
  var buffer = "", stack1;
  buffer += "\n      <a href='/badges/criteria/";
  foundHelper = helpers.config_id;
  stack1 = foundHelper || depth0.config_id;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "config_id", { hash: {} }); }
  buffer += escapeExpression(stack1) + "/";
  foundHelper = helpers.config_nonce;
  stack1 = foundHelper || depth0.config_nonce;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "config_nonce", { hash: {} }); }
  buffer += escapeExpression(stack1) + "?user=";
  foundHelper = helpers.nonce;
  stack1 = foundHelper || depth0.nonce;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "nonce", { hash: {} }); }
  buffer += escapeExpression(stack1) + "'>";
  foundHelper = helpers.name;
  stack1 = foundHelper || depth0.name;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "name", { hash: {} }); }
  buffer += escapeExpression(stack1) + "</a>\n    ";
  return buffer;}

function program3(depth0,data) {
  
  var buffer = "", stack1;
  buffer += "\n      ";
  foundHelper = helpers.name;
  stack1 = foundHelper || depth0.name;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "name", { hash: {} }); }
  buffer += escapeExpression(stack1) + "\n    ";
  return buffer;}

function program5(depth0,data) {
  
  
  return "\n      <img src='/add.png' alt='manually awarded' title='manually awarded'/>\n    ";}

function program7(depth0,data) {
  
  var buffer = "", stack1, stack2;
  buffer += "\n      ";
  foundHelper = helpers.awarded;
  stack1 = foundHelper || depth0.awarded;
  stack2 = helpers['if'];
  tmp1 = self.program(8, program8, data);
  tmp1.hash = {};
  tmp1.fn = tmp1;
  tmp1.inverse = self.program(10, program10, data);
  stack1 = stack2.call(depth0, stack1, tmp1);
  if(stack1 || stack1 === 0) { buffer += stack1; }
  buffer += "\n    ";
  return buffer;}
function program8(depth0,data) {
  
  
  return "\n        <img src='/check.gif' alt='earned' title='earned'/>\n      ";}

function program10(depth0,data) {
  
  var buffer = "", stack1, stack2;
  buffer += "\n        ";
  foundHelper = helpers.pending;
  stack1 = foundHelper || depth0.pending;
  stack2 = helpers['if'];
  tmp1 = self.program(11, program11, data);
  tmp1.hash = {};
  tmp1.fn = tmp1;
  tmp1.inverse = self.program(14, program14, data);
  stack1 = stack2.call(depth0, stack1, tmp1);
  if(stack1 || stack1 === 0) { buffer += stack1; }
  buffer += "\n      ";
  return buffer;}
function program11(depth0,data) {
  
  var buffer = "", stack1, stack2;
  buffer += "\n          <img src='/warning.png' alt='pending approval' class='earn_badge' title='earned, needs approval. click to manually award'/>\n          ";
  foundHelper = helpers.evidence_url;
  stack1 = foundHelper || depth0.evidence_url;
  stack2 = helpers['if'];
  tmp1 = self.program(12, program12, data);
  tmp1.hash = {};
  tmp1.fn = tmp1;
  tmp1.inverse = self.noop;
  stack1 = stack2.call(depth0, stack1, tmp1);
  if(stack1 || stack1 === 0) { buffer += stack1; }
  buffer += "\n          <form class='form form-inline' method='POST' action='/badges/award/";
  foundHelper = helpers.badge_placement_config_id;
  stack1 = foundHelper || depth0.badge_placement_config_id;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "badge_placement_config_id", { hash: {} }); }
  buffer += escapeExpression(stack1) + "/";
  foundHelper = helpers.id;
  stack1 = foundHelper || depth0.id;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "id", { hash: {} }); }
  buffer += escapeExpression(stack1) + "' style='visibility: hidden; display: inline; margin-left: 10px;'>\n            <input type='hidden' name='user_name' value='";
  foundHelper = helpers.name;
  stack1 = foundHelper || depth0.name;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "name", { hash: {} }); }
  buffer += escapeExpression(stack1) + "'/>\n            <button class='btn btn-primary' type='submit'><span class='icon-check icon-white'></span> Award Badge</button>\n          </form>\n        ";
  return buffer;}
function program12(depth0,data) {
  
  var buffer = "", stack1;
  buffer += "\n            <a href='";
  foundHelper = helpers.evidence_url;
  stack1 = foundHelper || depth0.evidence_url;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "evidence_url", { hash: {} }); }
  buffer += escapeExpression(stack1) + "' target='_blank' class='evidence_link label label-info'>evidence</a>&nbsp;\n          ";
  return buffer;}

function program14(depth0,data) {
  
  var buffer = "", stack1;
  buffer += "\n          <img src='/redx.png' alt='not earned' class='earn_badge' title='not earned. click to manually award'/>\n          <form class='form form-inline' method='POST' action='/badges/award/";
  foundHelper = helpers.badge_placement_config_id;
  stack1 = foundHelper || depth0.badge_placement_config_id;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "badge_placement_config_id", { hash: {} }); }
  buffer += escapeExpression(stack1) + "/";
  foundHelper = helpers.id;
  stack1 = foundHelper || depth0.id;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "id", { hash: {} }); }
  buffer += escapeExpression(stack1) + "' style='visibility: hidden; display: inline; margin-left: 10px;'>\n            <input type='hidden' name='user_name' value='";
  foundHelper = helpers.name;
  stack1 = foundHelper || depth0.name;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "name", { hash: {} }); }
  buffer += escapeExpression(stack1) + "'/>\n            <button class='btn btn-primary' type='submit'><span class='icon-check icon-white'></span> Award Badge</button>\n          </form>\n        ";
  return buffer;}

function program16(depth0,data) {
  
  var buffer = "", stack1;
  buffer += "\n      ";
  foundHelper = helpers.issued;
  stack1 = foundHelper || depth0.issued;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "issued", { hash: {} }); }
  buffer += escapeExpression(stack1) + "\n    ";
  return buffer;}

function program18(depth0,data) {
  
  
  return "\n      &nbsp;\n    ";}

  buffer += "<tr>\n  <td>\n    ";
  foundHelper = helpers.awarded;
  stack1 = foundHelper || depth0.awarded;
  stack2 = helpers['if'];
  tmp1 = self.program(1, program1, data);
  tmp1.hash = {};
  tmp1.fn = tmp1;
  tmp1.inverse = self.program(3, program3, data);
  stack1 = stack2.call(depth0, stack1, tmp1);
  if(stack1 || stack1 === 0) { buffer += stack1; }
  buffer += "\n  </td>\n  <td>\n    ";
  foundHelper = helpers.manually_awarded;
  stack1 = foundHelper || depth0.manually_awarded;
  stack2 = helpers['if'];
  tmp1 = self.program(5, program5, data);
  tmp1.hash = {};
  tmp1.fn = tmp1;
  tmp1.inverse = self.program(7, program7, data);
  stack1 = stack2.call(depth0, stack1, tmp1);
  if(stack1 || stack1 === 0) { buffer += stack1; }
  buffer += "\n  </td>\n  <td>\n    ";
  foundHelper = helpers.issued;
  stack1 = foundHelper || depth0.issued;
  stack2 = helpers['if'];
  tmp1 = self.program(16, program16, data);
  tmp1.hash = {};
  tmp1.fn = tmp1;
  tmp1.inverse = self.program(18, program18, data);
  stack1 = stack2.call(depth0, stack1, tmp1);
  if(stack1 || stack1 === 0) { buffer += stack1; }
  buffer += "\n  </td>\n</tr>\n";
  return buffer;});
})();
