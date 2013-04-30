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
  property :settings, Json
  
  def as_json(host_with_port)
    settings = self.settings || BadgeHelper.issuer
    {
      'name' => settings['name'],
      'url' => settings['url'],
      'description' => settings['description'],
      'image' => settings['image'],
      'email' => settings['email'],
      'revocationList' => "#{BadgeHelper.protocol}://#{host_with_port}/api/v1/organizations/#{self.id || 'default'}/revocations"
    }
  end
  
  def to_json(host_with_port)
    as_json(host_with_port).to_json
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
    conf.value = Digest::MD5.hexdigest(Time.now.to_i.to_s + rand.to_s).to_s
    conf.shared_secret = Digest::MD5.hexdigest(Time.now.to_i.to_s + rand.to_s + conf.value)
    conf.save
    conf
  end
end

class UserConfig
  include DataMapper::Resource
  property :id, Serial
  property :user_id, String
  property :access_token, String, :length => 256
  property :domain_id, Integer
  property :name, String, :length => 256
  property :global_user_id, String, :length => 256
  belongs_to :domain
  
  def host
    self.domain && self.domain.host
  end
end

class BadgeConfig
  include DataMapper::Resource
  property :id, Serial
  property :course_id, String
  property :placement_id, String
  property :nonce, String
  property :external_config_id, Integer
  property :organization_id, Integer
  property :domain_id, Integer
  property :settings, Json
  property :root_id, Integer
  property :reference_code, String
  
  before :save, :generate_nonce
  belongs_to :external_config
  belongs_to :organization
  
  def as_json(host_with_port)
    settings = self.settings || {}
    image = settings['badge_url'] || "/badges/default.png"
    image = host_with_port + image if image.match(/^\//)
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
  
  def org_id
    if self.organization && self.organization.settings
      "#{self.organization_id}-#{self.organization.settings['name'].downcase.gsub(/[^\w]+/, '-')[0, 30]}"
    else
      "default"
    end
  end

  def root_settings
    conf = self
    if self.root_id
      conf = BadgeConfig.first(:id => self.root_id) || self
    end
    conf.settings || {}
  end
  
  def root_nonce
    conf = self
    if self.root_id
      conf = BadgeConfig.first(:id => self.root_id) || self
    end
    conf.nonce
  end
  
  def generate_nonce
    self.nonce ||= Digest::MD5.hexdigest(Time.now.to_i.to_s + rand.to_s)
    self.reference_code ||= Digest::MD5.hexdigest(Time.now.to_i.to_s + rand.to_s)
  end
  
  def set_root_from_reference_code(code)
    root = BadgeConfig.first(:reference_code => code)
    if root
      self.root_id = root.id
    else
      self.root_id = nil
    end
  end
  
  def configured?
    settings && settings['badge_url'] && settings['min_percent']
  end
  
  def modules_required?
    settings && settings['modules']
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
  
  def requirements_met?(percent, completed_module_ids)
    if credit_based?
      credits = required_score_met?(percent) ? settings['credits_for_final_score'].to_f : 0
      settings['modules'].each do |id, name, credit|
        if completed_module_ids.include?(id.to_i)
          credits += credit
        end
      end
      credits > 0 && credits > settings['required_credits'].to_f
    else
      required_modules_completed?(completed_module_ids) && required_score_met?(percent)
    end
  end
end

class CourseConfig
  include DataMapper::Resource
  property :id, Serial
  property :course_id, String
  property :nonce, String
  property :domain_id, Integer
  property :settings, Json
  property :root_id, Integer
  property :reference_code, String
  
  before :save, :generate_nonce
  
  def root_settings
    conf = self
    if self.root_id
      conf = CourseConfig.first(:id => self.root_id) || self
    end
    conf.settings || {}
  end
  
  def root_nonce
    conf = self
    if self.root_id
      conf = CourseConfig.first(:id => self.root_id) || self
    end
    conf.nonce
  end
  
  def generate_nonce
    self.nonce ||= Digest::MD5.hexdigest(Time.now.to_i.to_s + rand.to_s)
    self.reference_code ||= Digest::MD5.hexdigest(Time.now.to_i.to_s + rand.to_s)
  end
  
  def set_root_from_reference_code(code)
    root = CourseConfig.first(:reference_code => code)
    if root
      self.root_id = root.id
    else
      self.root_id = nil
    end
  end
  
  def configured?
    settings && settings['badge_url'] && settings['min_percent']
  end
  
  def modules_required?
    settings && settings['modules']
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
  
  def requirements_met?(percent, completed_module_ids)
    required_modules_completed?(completed_module_ids) && required_score_met?(percent)
  end
end

class Badge
  include DataMapper::Resource
  property :id, Serial
  property :placement_id, String
  property :course_id, String
  property :user_id, String
  property :domain_id, Integer
  property :badge_url, String, :length => 256
  property :nonce, String
  property :badge_config_id, Integer
  property :course_config_id, Integer
  property :name, String, :length => 256
  property :user_full_name, String, :length => 256
  property :description, Text
  property :recipient, String, :length => 512
  property :salt, String, :length => 256
  property :issued, DateTime
  property :email, String
  property :manual_approval, Boolean
  property :public, Boolean
  property :state, String
  property :global_user_id, String, :length => 256
  property :issuer_name, String
  property :issuer_image_url, String
  property :issuer_org, String
  property :issuer_url, String
  property :issuer_email, String
  
  belongs_to :course_config
  belongs_to :badge_config
  before :save, :generate_defaults
  
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
      :evidence => "#{BadgeHelper.protocol}://#{host_with_port}/badges/criteria/#{self.badge_config_id}/#{self.config_nonce}?user=#{self.nonce}"
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
    self.badge_config ||= BadgeConfig.first(:placement_id => self.placement_id, :domain_id => self.domain_id)
    user_config = UserConfig.first(:user_id => self.user_id, :domain_id => self.domain_id)
    self.global_user_id = user_config.global_user_id if user_config
    true
  end
  
  def user_name
    conf = UserConfig.first(:user_id => self.user_id, :domain_id => self.domain_id)
    (conf && conf.name) || self.user_full_name
  end
  
  def config_nonce
    self.badge_config ||= BadgeConfig.first(:placement_id => self.placement_id, :domain_id => self.domain_id)
    self.badge_config && self.badge_config.root_nonce
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
  
  def self.generate_badge(params, badge_config, name, email)
    settings = badge_config.settings || {}
    badge = self.first_or_new(:user_id => params['user_id'], :badge_config_id => badge_config.id)
    badge.placement_id = badge_config.placement_id
    badge.domain_id = badge_config.domain_id

    if badge_config.settings && badge_config.settings['org'] && badge_config.settings['org'].is_a?(Hash)
      badge.issuer_image_url = badge_config.settings['org']['image']
      badge.issuer_org = badge_config.settings['org']['name']
      badge.issuer_url = badge_config.settings['org']['url']
      badge.issuer_email = badge_config.settings['org']['email']
    end

    badge.issuer_name = BadgeHelper.issuer['name']
    badge.badge_config = badge_config
    badge.name = settings['badge_name']
    badge.email = email
    badge.user_full_name = name || params['user_name']
    badge.description = settings['badge_description']
    badge.badge_url = settings['badge_url']
    badge
  end
  
  def self.manually_award(params, badge_config, name, email)
    badge = generate_badge(params, badge_config, name, email)
    badge.manual_approval = true unless badge.pending?
    badge.state = 'awarded'
    badge.issued = DateTime.now
    badge.save
    badge
  end
  
  def self.complete(params, badge_config, name, email)
    settings = badge_config.settings || {}
    badge = generate_badge(params, badge_config, name, email)
    badge.state ||= settings['manual_approval'] ? 'pending' : 'awarded'
    badge.save
    badge
  end
end

