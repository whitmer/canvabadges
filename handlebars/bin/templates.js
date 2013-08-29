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
  foundHelper = helpers.badge_config_id;
  stack1 = foundHelper || depth0.badge_config_id;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "badge_config_id", { hash: {} }); }
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
  foundHelper = helpers.badge_config_id;
  stack1 = foundHelper || depth0.badge_config_id;
  if(typeof stack1 === functionType) { stack1 = stack1.call(depth0, { hash: {} }); }
  else if(stack1=== undef) { stack1 = helperMissing.call(depth0, "badge_config_id", { hash: {} }); }
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