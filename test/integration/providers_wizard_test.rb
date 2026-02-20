require "test_helper"

class ProvidersWizardTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:one)
    @user = users(:one)
    @space = spaces(:one)
  end

  test "should get wizard step 1" do
    sign_in_as(@user)
    set_tenant(@account)
    
    get wizard_providers_path
    assert_response :success
    assert_select "h2", "Choose your AI Provider"
    assert_select "input[type=radio][name=provider_type]", 3
  end

  test "should proceed from step 1 to step 2" do
    sign_in_as(@user)
    set_tenant(@account)
    
    post wizard_step_providers_path, params: { provider_type: "openai" }
    assert_redirected_to wizard_providers_path
    follow_redirect!
    
    assert_response :success
    assert_select "h2", "Authenticate with OpenAI"
    assert_select "input[type=password][name=api_key]"
  end

  test "should complete wizard and create provider" do
    sign_in_as(@user)
    set_tenant(@account)
    
    # Setup: Complete steps 1-3
    post wizard_step_providers_path, params: { provider_type: "openai" }
    follow_redirect!
    post wizard_step_providers_path, params: { api_key: "sk-test123" }
    follow_redirect!
    post wizard_step_providers_path
    follow_redirect!
    
    # Step 4: Configure and save
    assert_difference("Provider.count", 1) do
      post wizard_step_providers_path, params: { name: "My OpenAI", enabled: "1" }
    end
    
    assert_redirected_to providers_path
    follow_redirect!
    assert_select ".alert-success", /Provider.*was successfully added/
    
    # Verify provider was created correctly
    provider = Provider.last
    assert_equal "My OpenAI", provider.name
    assert_equal "openai", provider.provider_type
    assert_equal "sk-test123", provider.api_key
    assert provider.enabled
  end

  test "should cancel wizard" do
    sign_in_as(@user)
    set_tenant(@account)
    
    # Setup: Start wizard
    get wizard_providers_path
    post wizard_step_providers_path, params: { provider_type: "openai" }
    
    # Cancel wizard
    post wizard_cancel_providers_path
    assert_redirected_to providers_path
    
    # Verify session was cleared
    assert_nil session[:provider_wizard]
  end

  test "should test connection via AJAX" do
    sign_in_as(@user)
    set_tenant(@account)
    
    # Setup: Get to step 3
    post wizard_step_providers_path, params: { provider_type: "github" }
    follow_redirect!
    post wizard_step_providers_path, params: { api_key: "ghp_test123" }
    follow_redirect!
    
    # Test connection via AJAX
    post test_connection_providers_path,
         params: { provider_type: "github", api_key: "ghp_test123" },
         as: :json
    
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["success"]
    assert json_response["models"].is_a?(Array)
    assert_includes json_response["models"], "Phi-3-mini-4k-instruct"
  end

  test "should handle all provider types in step 1" do
    sign_in_as(@user)
    set_tenant(@account)
    
    get wizard_providers_path
    assert_response :success
    
    # Check all provider options exist
    assert_select "input[type=radio][value=openai]"
    assert_select "input[type=radio][value=anthropic]"
    assert_select "input[type=radio][value=github]"
    
    # Check provider descriptions
    assert_select "h3", "OpenAI"
    assert_select "h3", "Anthropic"
    assert_select "h3", "GitHub Models"
  end
end
