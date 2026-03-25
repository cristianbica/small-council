require "test_helper"

class ProvidersSinglePageTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:one)
    @user = users(:one)
  end

  test "new page shows provider picker" do
    sign_in_as(@user)
    set_tenant(@account)

    get new_provider_path

    assert_response :success
    assert_select "h1", "Add Provider"
    assert_select "h2", "OpenAI"
    assert_select "h2", "OpenRouter"
    assert_select "h2", "Anthropic"
    assert_select "turbo-frame#provider_form_frame"
  end

  test "openai form loads in turbo frame" do
    sign_in_as(@user)
    set_tenant(@account)

    get new_provider_path(provider_type: "openai"), headers: { "Turbo-Frame" => "provider_form_frame" }

    assert_response :success
    assert_select "input[name='provider[provider_type]'][value='openai']"
    assert_select "input[name='provider[api_key]']"
    assert_select "input[name='provider[organization_id]']"
    assert_select "form[data-turbo-frame='_top']"
    assert_select "button", text: "Test Connection"
    assert_select "input[type='submit'][value='Create Provider'][disabled]"
  end

  test "openrouter form loads in turbo frame" do
    sign_in_as(@user)
    set_tenant(@account)

    get new_provider_path(provider_type: "openrouter"), headers: { "Turbo-Frame" => "provider_form_frame" }

    assert_response :success
    assert_select "input[name='provider[provider_type]'][value='openrouter']"
    assert_select "input[name='provider[api_key]']"
    assert_select "input[name='provider[organization_id]']", count: 0
    assert_select "form[data-turbo-frame='_top']"
    assert_select "button", text: "Test Connection"
    assert_select "input[type='submit'][value='Create Provider'][disabled]"
  end

  test "anthropic form loads in turbo frame" do
    sign_in_as(@user)
    set_tenant(@account)

    get new_provider_path(provider_type: "anthropic"), headers: { "Turbo-Frame" => "provider_form_frame" }

    assert_response :success
    assert_select "input[name='provider[provider_type]'][value='anthropic']"
    assert_select "input[name='provider[api_key]']"
    assert_select "input[name='provider[organization_id]']", count: 0
    assert_select "form[data-turbo-frame='_top']"
    assert_select "button", text: "Test Connection"
    assert_select "input[type='submit'][value='Create Provider'][disabled]"
  end

  test "test connection endpoint returns success payload" do
    sign_in_as(@user)
    set_tenant(@account)

    AI::Client.stubs(:test_connection).returns({ success: true, model: "gpt-4o-mini" })
    AI::Client.stubs(:list_models).returns([
      { id: "gpt-4", name: "GPT-4", provider: "openai" }
    ])

    post test_connection_providers_path,
         params: { provider_type: "openai", api_key: "sk-test123" },
         as: :json

    assert_response :success
    response_json = JSON.parse(response.body)
    assert response_json["success"]
    assert_includes response_json["models"], "gpt-4"
  end

  test "create does not invoke provider connection tester" do
    sign_in_as(@user)
    set_tenant(@account)

    ProviderConnectionTester.expects(:test).never

    assert_difference("Provider.count", 1) do
      post providers_path, params: {
        provider: {
          name: "OpenAI Direct Save",
          provider_type: "openai",
          api_key: "sk-test123",
          enabled: "1"
        }
      }
    end

    assert_redirected_to providers_path
    assert_not_includes response.redirect_url, "api_key="
  end
end
