require 'dm-core'
require 'dm-migrations'
require 'dm-types'
require 'sinatra/base'

class Domain
  include DataMapper::Resource
  property :id, Serial
  property :host, String
  property :name, String
end

class Organization
  include DataMapper::Resource
  property :id, Serial
  property :host, String
  property :settings, Json
  
  def as_json
    host_with_port = self.host
    image = (settings && settings['image']) || "/organizations/default.png"
    if !image.match(/:\/\//)
      image = "#{BadgeHelper.protocol}://" + host_with_port + image
    end
    settings = self.settings || BadgeHelper.issuer
    {
      'name' => settings['name'],
      'url' => settings['url'],
      'description' => settings['description'],
      'image' => image,
      'email' => settings['email'],
      'revocationList' => "#{BadgeHelper.protocol}://#{host_with_port}/api/v1/organizations/#{self.id || 'default'}/revocations.json"
    }
  end
  
  def default?
    settings['default'] == true
  end
  
  def to_json
    as_json.to_json
  end
  
  def org_id
    "#{self.id}-#{self.settings['name'].downcase.gsub(/[^\w]+/, '-')[0, 30]}"
  end
end

class ExternalConfig
  include DataMapper::Resource
  property :id, Serial
  property :config_type, String
  property :app_name, String
  property :organization_id, Integer
  property :value, String
  property :shared_secret, String, :length => 256
  
  def self.generate(name)
    conf = ExternalConfig.first_or_new(:config_type => 'lti', :app_name => name)
    conf.value ||= Digest::MD5.hexdigest(Time.now.to_i.to_s + rand.to_s).to_s
    conf.shared_secret ||= Digest::MD5.hexdigest(Time.now.to_i.to_s + rand.to_s + conf.value)
    conf.save
    conf
  end
end

class UserConfig
  include DataMapper::Resource
  property :id, Serial
  property :user_id, String
  property :access_token, String, :length => 512
  property :domain_id, Integer
  property :name, String, :length => 256
  property :image, String, :length => 512
  property :global_user_id, String, :length => 256
  belongs_to :domain
  
  def host
    self.domain && self.domain.host
  end
  
  def profile_url
    if host
      "#{BadgeHelper.protocol}://" + host + "/users/" + self.user_id
    else
      "http://www.instructure.com"
    end
  end
  
  def check_badge_status(badge_placement_config, params, name, email)
    scores_json = CanvasAPI.api_call("/api/v1/courses/#{badge_placement_config.course_id}?include[]=total_scores", self)
    modules_json = CanvasAPI.api_call("/api/v1/courses/#{badge_placement_config.course_id}/modules", self) if badge_placement_config.modules_required?
    modules_json ||= []
    completed_module_ids = modules_json.select{|m| m['completed_at'] }.map{|m| m['id'] }.compact
    unless scores_json
      return "<h3>Error getting data from Canvas</h3>"
    end
  
    student = scores_json['enrollments'].detect{|e|  e['role'].downcase == 'studentenrollment' }
    student['computed_final_score'] ||= 0 if student
  
    if student
      if badge_placement_config.requirements_met?(student['computed_final_score'], completed_module_ids)
        params['credits_earned'] = badge_placement_config.credits_earned(student['computed_final_score'], completed_module_ids)
        if !email
          raise "You need to set an email address in Canvas before you can earn any badges."
        end
        badge = Badge.complete(params, badge_placement_config, name, email)
      elsif !badge
        badge = Badge.generate_badge({'user_id' => self.user_id}, badge_placement_config, name, email)
        badge.save
      end
    end
    return {
      :completed_module_ids => completed_module_ids,
      :badge_config => badge_placement_config.badge_config,
      :badge_placement_config => badge_placement_config,
      :user_config => self,
      :badge => badge,
      :student => student
    }
  end
end

class BadgeConfigOwner
  include DataMapper::Resource
  property :id, Serial
  property :user_config_id, Integer
  property :badge_config_id, Integer
  property :badge_placement_config_id, Integer
  belongs_to :badge_config
  belongs_to :user_config
  belongs_to :badge_placement_config
end

class BadgeConfig
  include DataMapper::Resource
  property :id, Serial
  property :course_id, String # deprecated
  property :placement_id, String # deprecated
  property :teacher_user_config_id, Integer # deprecated
  property :nonce, String
  property :external_config_id, Integer # TODO: how is this used?
  property :organization_id, Integer
  property :domain_id, Integer # deprecated
  property :settings, Json # partially deprecated
  property :root_id, Integer # deprecated
  property :reference_code, String # deprecated
  property :reuse_code, String
  property :public, Boolean
  property :updated_at, DateTime
  
  before :save, :generate_nonce
  belongs_to :external_config
  belongs_to :organization
  has n, :badge_placement_configs
  
  def as_json(host_with_port)
    settings = self.settings || {}
    image = settings['badge_url'] || "/badges/default.png"
    image = "#{BadgeHelper.protocol}://" + host_with_port + image if image.match(/^\//)
    {
      :name => settings['badge_name'],
      :description => settings['badge_description'],
      :image => image,
      :criteria => "#{BadgeHelper.protocol}://#{host_with_port}/badges/criteria/#{self.id}/#{self.nonce}",
      :issuer => "#{BadgeHelper.protocol}://#{host_with_port}/api/v1/organizations/#{self.org_id}.json",
      :alignment => [], # TODO
      :tags => [] # TODO
    }
  end
  
  def to_json(host_with_port)
    as_json(host_with_port).to_json
  end
  
  def self.generate_badge_placement_configs
    BadgeConfig.all.each{|bc| bc.generate_badge_placement_config }
  end
  
  def generate_badge_placement_config
    if self.placement_id
      bc = BadgePlacementConfig.first_or_new(:placement_id => self.placement_id, :domain_id => self.domain_id)
      bc.course_id ||= self.course_id
      bc.teacher_user_config_id ||= self.teacher_user_config_id
      bc.external_config_id ||= self.external_config_id
      bc.organization_id ||= self.organization_id
      bc.domain_id ||= self.domain_id
      bc.updated_at = DateTime.now
      bc.set_badge_config(self)
      bc.save
      bc
    end
  end
  
  def org_id
    if self.organization && self.organization.settings
      "#{self.organization_id}-#{self.organization.settings['name'].downcase.gsub(/[^\w]+/, '-')[0, 30]}"
    else
      "default"
    end
  end

  def generate_nonce
    self.nonce ||= Digest::MD5.hexdigest(Time.now.to_i.to_s + rand.to_s)
    self.reuse_code ||= Digest::MD5.hexdigest(Time.now.to_i.to_s + rand.to_s)
  end
  
  def approve_to_pending?
    settings && (settings['manual_approval'] || settings['require_evidence'])
  end
  
  def update_counts
    self.settings ||= {}
    self.settings['awarded_count'] = Badge.all(:badge_config_id => self.id, :state => 'awarded').count
    self.save
  end
  
  def configured?
    settings && settings['badge_url']
  end
end

class BadgePlacementConfig
  include DataMapper::Resource
  property :id, Serial
  property :badge_config_id, Integer
  property :course_id, String
  property :placement_id, String
  property :teacher_user_config_id, Integer
  property :author_user_config_id, Integer
  property :nonce, String # deprecated
  property :external_config_id, Integer # deprecated
  property :organization_id, Integer # deprecated
  property :domain_id, Integer
  property :settings, Json # partially deprecated
  property :root_id, Integer # deprecated
  property :reference_code, String # deprecated
  property :public, Boolean
  property :updated_at, DateTime
  
  belongs_to :badge_config
  belongs_to :external_config
  belongs_to :organization
  
  def merged_settings
    settings = (self.badge_config && self.badge_config.settings) || {}
    settings.merge(self.settings || {})
  end
  
  def set_badge_config(badge_config)
    self.badge_config_id = badge_config.id
    badge_settings = badge_config.settings || {}
    placement_settings = self.settings || {}
    if badge_settings['min_percent'] != nil && placement_settings['min_percent'] == nil
      placement_settings['manual_approval'] = badge_settings['manual_approval']
      placement_settings['require_evidence'] = badge_settings['require_evidence']
      placement_settings['credit_based'] = badge_settings['credit_based']
      placement_settings['required_credits'] = badge_settings['requird_credits'].to_f.round(1)
      placement_settings['min_percent'] = badge_settings['min_percent'].to_f
      placement_settings['hours'] = badge_settings['hours'].to_f.round(1)
      placement_settings['hours'] = nil if placement_settings['hours'] == 0
      placement_settings['credits_for_final_score'] = badge_settings['credits_for_final_score'].to_f.round(1)
      placement_settings['modules'] = badge_settings['modules']
      placement_settings['total_credits'] = badge_settings['total_credits']
    
      self.settings = placement_settings
    end
    first_placement = badge_config.badge_placement_configs.first
    self.settings['prior_resource_link_id'] = first_placement.placement_id if first_placement

    self.save
    Badge.all(:badge_config_id => badge_config.id, :badge_placement_config_id => nil).update(:badge_placement_config_id => self.id)
    Badge.all(:badge_config_id => badge_config.id, :course_id => nil).update(:course_id => self.course_id)
  end
  
  def check_for_awardees
    teacher_config = self.teacher_user_config_id && UserConfig.first(:id => self.teacher_user_config_id)
    if teacher_config
      # get the paginated list of students
      # for each student, check if they already have a badge awarded
      # if not, check on award status
    end
  end
  
  def load_from_old_config(user_config, old_config=nil)
    self.settings ||= {}
    return nil if !self.settings['prior_resource_link_id'] || self.settings['already_loaded_from_old_config']
    old_config = BadgePlacementConfig.first(:placement_id => self.settings['prior_resource_link_id'], :domain_id => self.domain_id)
    if old_config
      # load config settings from previous badge config
      self.settings = old_config.settings
      
      # set to pending unless
      # able to get new module ids and map them correctly for module-configured badges
      self.settings['pending'] = true if old_config.modules_required?
      
      api_user = UserConfig.first(:id => self.teacher_user_config_id) || user_config
      if api_user && old_config.modules_required?
        # make an API call to get the module ids and try to map from old to new
        # map ids for module names and also credits_for values
        new_modules = []
        modules_json = CanvasAPI.api_call("/api/v1/courses/#{self.course_id}/modules", api_user) || []
        all_found = true
        old_config.settings['modules'].each do |id, str, credits|
          new_module = modules_json.detect{|m| m['name'] == str}
          if new_module
            new_modules << [new_module['id'].to_s, str, credits]
          else
            all_found = false
          end
        end
        self.settings['modules'] = new_modules
        self.settings['pending'] = !all_found
      end
      self.settings['already_loaded_from_old_config'] = true
      self.save
    end
  end
  
  def to_json(host_with_port)
    as_json(host_with_port).to_json
  end
  
  def approve_to_pending?
    settings && (settings['manual_approval'] || settings['require_evidence'])
  end
  
  def update_counts
    self.settings ||= {}
    self.settings['awarded_count'] = Badge.all(:badge_placement_config_id => self.id, :state => 'awarded').count
    self.save
    self.badge_config.update_counts
  end
  
  def pending?
    settings && settings['pending']
  end
  
  def award_only?
    settings && settings['award_only']
  end
  
  def configured?
    !!(self.settings && self.badge_config && self.badge_config.settings && self.badge_config.settings['badge_url'] && self.settings['min_percent'] && !self.pending? && !self.award_only?)
  end
  
  def modules_required?
    settings && settings['modules']
  end
  
  def evidence_required?
    settings && settings['require_evidence']
  end
  
  def credit_based?
    !!(settings && settings['credit_based'] && settings['required_credits'])
  end
  
  def required_modules
    (settings && settings['modules']) || []
  end
  
  def required_module_ids
    required_modules.map(&:first).map(&:to_i)
  end
  
  def required_modules_completed?(completed_module_ids)
    incomplete_module_ids = self.required_module_ids - completed_module_ids
    incomplete_module_ids.length == 0
  end
  
  def required_score_met?(percent)
    settings && percent >= settings['min_percent']
  end
  
  def credits_earned(percent, completed_module_ids)
    credits = required_score_met?(percent) ? settings['credits_for_final_score'].to_f : 0
    (settings['modules'] || []).each do |id, name, credit|
      if completed_module_ids.include?(id.to_i)
        credits += (credit || 0)
      end
    end
    credits
  end
  
  def requirements_met?(percent, completed_module_ids)
    if credit_based?
      credits = credits_earned(percent, completed_module_ids)
      credits > 0 && credits > settings['required_credits'].to_f
    else
      required_modules_completed?(completed_module_ids) && required_score_met?(percent)
    end
  end
end

class Badge
  include DataMapper::Resource
  property :id, Serial
  property :placement_id, String
  property :course_id, String
  property :user_id, String
  property :domain_id, Integer
  property :badge_url, Text
  property :nonce, String
  property :badge_config_id, Integer
  property :badge_placement_config_id, Integer
  property :name, String, :length => 256
  property :user_full_name, String, :length => 256
  property :description, Text
  property :credits_earned, Integer
  property :recipient, String, :length => 512
  property :salt, String, :length => 512
  property :issued, DateTime
  property :email, String
  property :evidence_url, String, :length => 4096
  property :manual_approval, Boolean
  property :public, Boolean
  property :state, String
  property :global_user_id, String, :length => 256
  property :issuer_name, String
  property :issuer_image_url, String
  property :issuer_org, String
  property :issuer_url, String
  property :issuer_email, String
  
  belongs_to :badge_config
  belongs_to :badge_placement_config
  before :save, :generate_defaults
  after :save, :check_for_notify_on_award
  
  def open_badge_json(host_with_port)
    {
      :uid => self.id.to_s,
      :recipient => {
        :identity => self.recipient,
        :type => "email",
        :hashed => true,
        :salt => self.salt
      },
      :badge => "#{BadgeHelper.protocol}://#{host_with_port}/api/v1/badges/summary/#{self.badge_config_id}/#{self.config_nonce}.json",
      :verify => {
        :type => "hosted",
        :url => "#{BadgeHelper.protocol}://#{host_with_port}/api/v1/badges/data/#{self.badge_config_id}/#{self.user_id}/#{self.nonce}.json"
      },
      :issuedOn => (self.issued && self.issued.strftime("%Y-%m-%d")),
      :image => self.badge_url,
      :evidence => (self.evidence_url || "#{BadgeHelper.protocol}://#{host_with_port}/badges/criteria/#{self.badge_config_id}/#{self.config_nonce}?user=#{self.nonce}")
    }
  end
  
  def generate_defaults
    self.salt ||= Time.now.to_i.to_s
    self.nonce ||= Digest::MD5.hexdigest(self.salt + rand.to_s)
    self.issued ||= DateTime.now if self.awarded?
    if !self.recipient
      sha = Digest::SHA256.hexdigest(self.email + self.salt)
      self.recipient = "sha256$#{sha}"
    end
    self.badge_placement_config ||= BadgePlacementConfig.first(:placement_id => self.placement_id, :domain_id => self.domain_id)
    self.badge_config ||= self.badge_placement_config && self.badge_placement_config.badge_config
    user_config = UserConfig.first(:user_id => self.user_id, :domain_id => self.domain_id)
    self.global_user_id = user_config.global_user_id if user_config
    true
  end
  
  def check_for_notify_on_award
    # check if state just changed to awarded or completed, notify via email if that's the case
  end
  
  def user_name
    conf = UserConfig.first(:user_id => self.user_id, :domain_id => self.domain_id)
    (conf && conf.name) || self.user_full_name
  end
  
  def config_nonce
    self.badge_placement_config ||= BadgePlacementConfig.first(:placement_id => self.placement_id, :domain_id => self.domain_id)
    self.badge_config ||= self.badge_placement_config && self.badge_placement_config.badge_config
    self.badge_config && self.badge_config.nonce
  end
  
  def needing_evaluation?
    !awarded? && !pending?
  end
  
  def awarded?
    self.state == 'awarded'
  end
  
  def pending?
    self.state == 'pending'
  end
  
  def revoke
    self.state = 'revoked'
    save
  end
  
  def award
    self.state = 'awarded'
    save
  end
  
  def self.generate_badge(params, badge_placement_config, name, email)
    settings = badge_placement_config.merged_settings || {}
    badge = self.first_or_new(:user_id => params['user_id'], :badge_config_id => badge_placement_config.badge_config_id)
    badge.badge_placement_config = badge_placement_config
    badge.placement_id = badge_placement_config.placement_id
    badge.domain_id = badge_placement_config.domain_id
    badge.course_id = badge_placement_config.course_id

    if settings && settings['org'] && settings['org'].is_a?(Hash)
      badge.issuer_image_url = settings['org']['image']
      badge.issuer_org = settings['org']['name']
      badge.issuer_url = settings['org']['url']
      badge.issuer_email = settings['org']['email']
    end

    badge.issuer_name = BadgeHelper.issuer['name']
    badge.badge_config = badge_placement_config.badge_config
    badge.name = settings['badge_name']
    badge.email = email
    badge.state ||= 'unissued'
    badge.credits_earned = params['credits_earned'].to_i
    badge.user_full_name = name || params['user_name']
    badge.description = settings['badge_description']
    badge.badge_url = settings['badge_url']
    badge
  end
  
  def self.manually_award(params, badge_placement_config, name, email)
    badge = generate_badge(params, badge_placement_config, name, email)
    badge.manual_approval = true unless badge.pending?
    badge.state = 'awarded'
    badge.issued = DateTime.now
    badge.save
    badge_placement_config.update_counts
    badge
  end
  
  def self.complete(params, badge_placement_config, name, email)
    badge = generate_badge(params, badge_placement_config, name, email)
    badge.state = nil if badge.state == 'unissued'
    badge.state ||= badge_placement_config.approve_to_pending? ? 'pending' : 'awarded'
    badge.save
    badge_placement_config.update_counts
    badge
  end
end

