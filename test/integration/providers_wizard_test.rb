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
    assert_select "input[type=radio][name=provider_type]", 2
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

    # Mock the LLM::Client
    mock_client = mock
    LLM::Client.stubs(:new).returns(mock_client)
    mock_client.stubs(:test_connection).returns({ success: true, model: "gpt-4o-mini" })
    mock_client.stubs(:list_models).returns([
      { id: "gpt-4", name: "GPT-4", provider: "openai" }
    ])

    # Setup: Get to step 3
    post wizard_step_providers_path, params: { provider_type: "openai" }
    follow_redirect!
    post wizard_step_providers_path, params: { api_key: "sk-test123" }
    follow_redirect!

    # Test connection via AJAX
    post test_connection_providers_path,
         params: { provider_type: "openai", api_key: "sk-test123" },
         as: :json

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["success"]
    assert json_response["models"].is_a?(Array)
    assert_includes json_response["models"], "gpt-4"
  end

  test "should handle all provider types in step 1" do
    sign_in_as(@user)
    set_tenant(@account)

    get wizard_providers_path
    assert_response :success

    # Check all provider options exist
    assert_select "input[type=radio][value=openai]"
    assert_select "input[type=radio][value=openrouter]"

    # Check provider descriptions
    assert_select "h3", "OpenAI"
    assert_select "h3", "OpenRouter"
  end

  test "should go back from step 2 to step 1" do
    sign_in_as(@user)
    set_tenant(@account)

    # Setup: Get to step 2
    post wizard_step_providers_path, params: { provider_type: "openai" }
    follow_redirect!
    assert_select "h2", "Authenticate with OpenAI"

    # Go back to step 1
    post wizard_back_providers_path
    assert_redirected_to wizard_providers_path
    follow_redirect!

    assert_response :success
    assert_select "h2", "Choose your AI Provider"

    # Verify provider type is still remembered
    post wizard_step_providers_path, params: { provider_type: "openai" }
    follow_redirect!
    assert_select "h2", "Authenticate with OpenAI"
  end

  test "should go back from step 3 to step 2" do
    sign_in_as(@user)
    set_tenant(@account)

    # Setup: Get to step 3
    post wizard_step_providers_path, params: { provider_type: "openrouter" }
    follow_redirect!
    post wizard_step_providers_path, params: { api_key: "sk-or-test" }
    follow_redirect!
    assert_select "h2", "Test Connection"

    # Go back to step 2
    post wizard_back_providers_path
    assert_redirected_to wizard_providers_path
    follow_redirect!

    assert_response :success
    assert_select "h2", "Authenticate with OpenRouter"

    # Verify API key field is present
    assert_select "input[type=password][name=api_key]"
  end

  test "should create provider with default name when name is blank" do
    sign_in_as(@user)
    set_tenant(@account)

    # Setup: Complete steps 1-3
    post wizard_step_providers_path, params: { provider_type: "openrouter" }
    follow_redirect!
    post wizard_step_providers_path, params: { api_key: "sk-or-test123" }
    follow_redirect!
    post wizard_step_providers_path
    follow_redirect!

    # Step 4: Save with blank name (should use default)
    assert_difference("Provider.count", 1) do
      post wizard_step_providers_path, params: { name: "", enabled: "1" }
    end

    assert_redirected_to providers_path

    # Verify provider was created with default name
    provider = Provider.last
    assert_equal "OpenRouter", provider.name
  end

  test "should create disabled provider when enabled is unchecked" do
    sign_in_as(@user)
    set_tenant(@account)

    # Setup: Complete steps 1-3
    post wizard_step_providers_path, params: { provider_type: "openai" }
    follow_redirect!
    post wizard_step_providers_path, params: { api_key: "sk-test123" }
    follow_redirect!
    post wizard_step_providers_path
    follow_redirect!

    # Step 4: Save with enabled unchecked (Rails checkbox sends "0" when unchecked via hidden field)
    assert_difference("Provider.count", 1) do
      post wizard_step_providers_path, params: { name: "Disabled Provider", enabled: "0" }
    end

    provider = Provider.last
    assert_equal "Disabled Provider", provider.name
    assert_not provider.enabled
  end

  test "should show OpenAI organization ID field only for OpenAI" do
    sign_in_as(@user)
    set_tenant(@account)

    # OpenAI should show organization ID field
    post wizard_step_providers_path, params: { provider_type: "openai" }
    follow_redirect!
    assert_select "input[name=organization_id]"

    # Cancel and try OpenRouter
    post wizard_cancel_providers_path
    post wizard_step_providers_path, params: { provider_type: "openrouter" }
    follow_redirect!
    assert_select "input[name=organization_id]", count: 0
  end

  test "should handle test connection failure" do
    sign_in_as(@user)
    set_tenant(@account)

    # Mock the LLM::Client to return failure
    mock_client = mock
    LLM::Client.stubs(:new).returns(mock_client)
    mock_client.stubs(:test_connection).returns({ success: false, error: "Invalid API key" })

    # Test connection with invalid API key
    post test_connection_providers_path,
         params: { provider_type: "openai", api_key: "invalid_key" },
         as: :json

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_not json_response["success"]
    assert json_response["error"].present?
  end
end
