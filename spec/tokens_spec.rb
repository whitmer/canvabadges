require File.dirname(__FILE__) + '/spec_helper'

describe 'Token Aactions' do
  include Rack::Test::Methods
  
  def app
    Canvabadges
  end
  
  before :each do
    example_org
  end
  
  describe "token details page" do
    it "should fail gracefully if invalid parameters provided" do
      get "/token?id=asdf"
      last_response.should_not be_ok
      err = JSON.parse(last_response.body)
      err.should == {'error' => 'invalid token'}
      
      token = ExternalConfig.generate("cool one")
      get "/token?id=#{token.id}&confirmation=qwert"
      last_response.should_not be_ok
      err = JSON.parse(last_response.body)
      err.should == {'error' => 'invalid token'}
    end
    
    it "should fail gracefully if invalid confirmation" do
      token = ExternalConfig.generate("cool one")
      get "/token?id=#{token.id}&confirmation=qwert"
      last_response.should_not be_ok
      err = JSON.parse(last_response.body)
      err.should == {'error' => 'invalid token'}
    end
    
    it "should show token details if successfully found" do
      token = ExternalConfig.generate("cool one")
      token.confirmation.should_not == nil
      get "/token?id=#{token.id}&confirmation=#{token.confirmation}"
      last_response.should be_ok
      last_response.body.should match(token.value)
      last_response.body.should match(token.shared_secret)
    end
  end
  
  describe "token update organization" do
    it "should fail gracefully on invalid parameters" do
      post "/token/organization?id=asdf"
      last_response.should_not be_ok
      err = JSON.parse(last_response.body)
      err.should == {'error' => 'invalid token'}
      
      token = ExternalConfig.generate("cool one")
      post "/token/organization?id=#{token.id}&confirmation=qwert"
      last_response.should_not be_ok
      err = JSON.parse(last_response.body)
      err.should == {'error' => 'invalid token'}
    end
    
    it "should create a new organization if none exists" do
      token = ExternalConfig.generate("cool one")
      post "/token/organization?id=#{token.id}&confirmation=#{token.confirmation}", {
        'name' => "my org",
        'url' => "http://www.example.com",
        'image' => "http://www.example.com/img.png",
        'bacon' => "sizzling",
        'email' => "bob@example.com",
        'subdirectory' => 'hello'
      }
      last_response.should be_ok
      token.reload.organization_id.should_not == nil
      org = token.reload.organization
      org.settings['name'].should == "my org"
      org.settings['url'].should == "http://www.example.com"
      org.settings['image'].should == "http://www.example.com/img.png"
      org.settings['bacon'].should == nil
      org.settings['email'].should == "bob@example.com"
      org.host.should == "example.org/_hello"
    end
    
    it "should fall back to a default subdirectory name" do
      token = ExternalConfig.generate("cool one")
      post "/token/organization?id=#{token.id}&confirmation=#{token.confirmation}", {
      }
      last_response.should be_ok
      token.reload.organization_id.should_not == nil
      org = token.reload.organization
      org.host.should == "example.org/_organization"
    end
    
    it "should generate a new subdirectory name on collision" do
      token = ExternalConfig.generate("cool one")
      o = Organization.create(:host => "example.org/_bacon")
      post "/token/organization?id=#{token.id}&confirmation=#{token.confirmation}", {
        'subdirectory' => 'bacon'
      }
      last_response.should be_ok
      token.reload.organization_id.should_not == nil
      org = token.reload.organization
      org.host.should == "example.org/_bacon1"
    end
    
    it "should add the user as an editor when creating a new organization" do
      token = ExternalConfig.generate("cool one")
      post "/token/organization?id=#{token.id}&confirmation=#{token.confirmation}", {
        'name' => "my org",
        'url' => "http://www.example.com",
        'image' => "http://www.example.com/img.png",
        'bacon' => "sizzling",
        'email' => "bob@example.com",
        'subdirectory' => 'hello'
      }
      last_response.should be_ok
      token.reload.organization_id.should_not == nil
      org = token.reload.organization
      token.organization_editor?.should == true
    end
    
    it "should not allow updating an existing organization if not an editor" do
      token = ExternalConfig.generate("cool one")
      org = Organization.create
      token.organization_id = org.id
      token.save
      post "/token/organization?id=#{token.id}&confirmation=#{token.confirmation}", {
        'name' => "my org",
        'url' => "http://www.example.com",
        'image' => "http://www.example.com/img.png",
        'bacon' => "sizzling",
        'email' => "bob@example.com",
        'subdirectory' => 'hello'
      }
      last_response.should_not be_ok
      err = JSON.parse(last_response.body)
      err.should == {"error" => "not authorized"}
    end
    
    it "should update an existing organzization if an editor" do
      token = ExternalConfig.generate("cool one")
      org = Organization.create
      token.organization_id = org.id
      token.save
      token.connect_to_organization(org.editor_code)
      token.reload.organization_editor?.should == true
      post "/token/organization?id=#{token.id}&confirmation=#{token.confirmation}", {
        'name' => "my org",
        'url' => "http://www.example.com",
        'image' => "http://www.example.com/img.png",
        'bacon' => "sizzling",
        'email' => "bob@example.com",
        'subdirectory' => 'hello'
      }
      last_response.should be_ok
      token.reload.organization_id.should_not == nil
      org = token.reload.organization
      org.settings['name'].should == "my org"
      org.settings['url'].should == "http://www.example.com"
      org.settings['image'].should == "http://www.example.com/img.png"
      org.settings['bacon'].should == nil
      org.settings['email'].should == "bob@example.com"
      org.host.should == nil
    end
    
    it "should create a developer key config if oss and not created yet" do
      token = ExternalConfig.generate("cool one")
      post "/token/organization?id=#{token.id}&confirmation=#{token.confirmation}", {
        'name' => "my org",
        'url' => "http://www.example.com",
        'image' => "http://www.example.com/img.png",
        'bacon' => "sizzling",
        'email' => "bob@example.com",
        'subdirectory' => 'hello',
        'oss' => '1',
        'developer_key' => 'asdf',
        'developer_secret' => 'qwer'
      }
      last_response.should be_ok
      token.reload.organization_id.should_not == nil
      org = token.reload.organization
      org.settings['name'].should == "my org"
      org.settings['url'].should == "http://www.example.com"
      org.settings['image'].should == "http://www.example.com/img.png"
      org.settings['bacon'].should == nil
      org.settings['email'].should == "bob@example.com"
      org.host.should == "example.org/_hello"
      org.oss_config.should_not == nil
      org.oss_config.value.should == 'asdf'
      org.oss_config.shared_secret.should == 'qwer'
    end
    
    it "should update an existing developer key config if oss" do
      token = ExternalConfig.generate("cool one")
      org = Organization.create
      oss = ExternalConfig.create(:organization_id => org.id, :value => 'asdf', :shared_secret => 'qwer')
      token.connect_to_organization(org.editor_code)
      post "/token/organization?id=#{token.id}&confirmation=#{token.confirmation}", {
        'name' => "my org",
        'oss' => '1',
        'developer_key' => 'wert',
        'developer_secret' => 'sdfg'
      }
      last_response.should be_ok
      token.reload.organization_id.should_not == nil
      org2 = token.reload.organization
      org2.should == org
      org2.settings['name'].should == "my org"
      org2.oss_config.should_not == nil
      org2.oss_config.value.should == 'wert'
      org2.oss_config.shared_secret.should == 'sdfg'
    end
    
    it "should delete an existing developer key config if not oss" do
      token = ExternalConfig.generate("cool one")
      org = Organization.create
      oss = ExternalConfig.create(:organization_id => org.id, :config_type => 'canvas_oss_oauth', :value => 'asdf', :shared_secret => 'qwer')
      org.reload.oss_config.should == oss
      token.connect_to_organization(org.editor_code)
      post "/token/organization?id=#{token.id}&confirmation=#{token.confirmation}", {
        'name' => "my org",
        'developer_key' => 'wert',
        'developer_secret' => 'sdfg'
      }
      last_response.should be_ok
      token.reload.organization_id.should_not == nil
      org2 = token.reload.organization
      org2.should == org
      org2.settings['name'].should == "my org"
      org2.oss_config.should == nil
      ExternalConfig.first(:id => oss.id).should == nil
    end
  end
  
  describe "token connect organization" do
    it "should fail gracefully on invalid parameters" do
      post "/token/connect?id=asdf"
      last_response.should_not be_ok
      err = JSON.parse(last_response.body)
      err.should == {'error' => 'invalid token'}
      
      token = ExternalConfig.generate("cool one")
      post "/token/connect?id=#{token.id}&confirmation=qwert"
      last_response.should_not be_ok
      err = JSON.parse(last_response.body)
      err.should == {'error' => 'invalid token'}
    end
    
    it "should fail gracefully for an invalid editor code" do
      token = ExternalConfig.generate("cool one")
      org = Organization.create
      post "/token/connect?id=#{token.id}&confirmation=#{token.confirmation}", {
        'code' => "asdf"
      }
      last_response.should_not be_ok
      err = JSON.parse(last_response.body)
      err.should == {'error' => 'invalid code'}
    end
    
    it "should add the user as an editor when editor_code is provided" do
      token = ExternalConfig.generate("cool one")
      org = Organization.create
      post "/token/connect?id=#{token.id}&confirmation=#{token.confirmation}", {
        'code' => org.editor_code
      }
      last_response.should be_ok
      token.reload.organization_id.should == org.id
      token.organization_editor?.should == true
    end
    
    it "should add the user as a user when user_code is provided" do
      token = ExternalConfig.generate("cool one")
      org = Organization.create
      post "/token/connect?id=#{token.id}&confirmation=#{token.confirmation}", {
        'code' => org.user_code
      }
      last_response.should be_ok
      token.reload.organization_id.should == org.id
      token.organization_editor?.should == false
    end
  end
  
  describe "token disconnect organization" do
    it "should fail gracefully on invalid parameters" do
      post "/token/disconnect?id=asdf"
      last_response.should_not be_ok
      err = JSON.parse(last_response.body)
      err.should == {'error' => 'invalid token'}
      
      token = ExternalConfig.generate("cool one")
      post "/token/disconnect?id=#{token.id}&confirmation=qwert"
      last_response.should_not be_ok
      err = JSON.parse(last_response.body)
      err.should == {'error' => 'invalid token'}
    end
    
    it "should disconnect the user on valid parameters" do
      token = ExternalConfig.generate("cool one")
      org = Organization.create
      token.connect_to_organization(org.user_code)
      post "/token/disconnect?id=#{token.id}&confirmation=#{token.confirmation}"
      last_response.should be_ok
      token.reload.organization_id.should == nil
    end
    
    it "should delete the orgnazation if it no other users are connceted and it hasn't been used to create badges yet" do
      token = ExternalConfig.generate("cool one")
      org = Organization.create
      token.connect_to_organization(org.user_code)
      post "/token/disconnect?id=#{token.id}&confirmation=#{token.confirmation}"
      last_response.should be_ok
      token.reload.organization_id.should == nil
      Organization.first(:id => org.id).should == nil
    end
    
    it "should not delete the organization if other users are still connected" do
      token = ExternalConfig.generate("cool one")
      token2 = ExternalConfig.generate("another one")
      org = Organization.create
      token.connect_to_organization(org.user_code)
      token2.connect_to_organization(org.user_code)
      post "/token/disconnect?id=#{token.id}&confirmation=#{token.confirmation}"
      last_response.should be_ok
      token.reload.organization_id.should == nil
      Organization.first(:id => org.id).should_not == nil
    end
    
    it "should not delete the organization if it has been used to create badges" do
      token = ExternalConfig.generate("cool one")
      org = Organization.create
      BadgeConfig.create(:organization_id => org.id)
      token.connect_to_organization(org.user_code)
      post "/token/disconnect?id=#{token.id}&confirmation=#{token.confirmation}"
      last_response.should be_ok
      token.reload.organization_id.should == nil
      Organization.first(:id => org.id).should_not == nil
    end
  end
end
