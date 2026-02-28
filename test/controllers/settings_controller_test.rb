require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:one)
    @user = users(:one)
    @llm_model = llm_models(:one) rescue nil
    sign_in_as(@user)
    set_tenant(@account)
  end

  test "should get edit settings page" do
    get edit_settings_url
    assert_response :success
    assert_select "h1", /Settings/i
  end

  test "should update account settings with valid params" do
    # Create a default LLM model for the account if needed
    model = @account.llm_models.first || create_default_model

    patch settings_url, params: {
      account: {
        default_llm_model_id: model.id
      }
    }

    assert_redirected_to edit_settings_path
    assert_equal "Settings updated successfully.", flash[:notice]
    assert_equal model.id, @account.reload.default_llm_model_id
  end

  test "should not update settings with invalid params" do
    # Use invalid model ID
    patch settings_url, params: {
      account: {
        default_llm_model_id: "invalid"
      }
    }

    assert_response :unprocessable_entity
    assert_select "h1", /Settings/i
  end

  test "should require authentication for edit" do
    # Make request without authentication by using a new session
    get edit_settings_url, headers: { "HTTP_COOKIE" => "" }
    assert_redirected_to sign_in_url
  end

  test "should require authentication for update" do
    # Make request without authentication by using a new session
    patch settings_url, params: { account: { default_llm_model_id: 1 } }, headers: { "HTTP_COOKIE" => "" }
    assert_redirected_to sign_in_url
  end

  test "should only permit allowed params" do
    original_name = @account.name
    model = @account.llm_models.first || create_default_model

    patch settings_url, params: {
      account: {
        default_llm_model_id: model.id,
        name: "Hacked Name",
        slug: "hacked-slug"
      }
    }

    # Name and slug should not be changed (not in permitted params)
    assert_equal original_name, @account.reload.name
  end

  private

  def create_default_model
    provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )
    provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )
  end

  def sign_out
    delete session_url(Current.session) if Current.session
  end
end
