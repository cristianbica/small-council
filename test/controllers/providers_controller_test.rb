require "test_helper"

class ProvidersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
  end

  test "should redirect to sign in when not authenticated" do
    set_tenant(@account)
    get providers_url
    assert_redirected_to sign_in_url
  end

  test "should get index when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    get providers_url
    assert_response :success
  end

  test "should get new when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    get new_provider_url
    assert_response :success
  end

  test "should create provider when authenticated" do
    sign_in_as(@user)
    set_tenant(@account)
    assert_difference("Provider.count") do
      post providers_url, params: {
        provider: {
          name: "OpenAI Test",
          provider_type: "openai",
          api_key: "sk-test123"
        }
      }
    end
    assert_redirected_to providers_url
  end

  test "should fail to create provider without name" do
    sign_in_as(@user)
    set_tenant(@account)
    assert_no_difference("Provider.count") do
      post providers_url, params: {
        provider: {
          provider_type: "openai",
          api_key: "test-key"
          # missing name
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "should get edit for provider" do
    sign_in_as(@user)
    set_tenant(@account)
    provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "key"
    )
    get edit_provider_url(provider)
    assert_response :success
  end

  test "should update provider" do
    sign_in_as(@user)
    set_tenant(@account)
    provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "key"
    )
    patch provider_url(provider), params: {
      provider: { name: "Updated Provider" }
    }
    assert_redirected_to providers_url

    provider.reload
    assert_equal "Updated Provider", provider.name
  end

  test "should destroy provider" do
    sign_in_as(@user)
    set_tenant(@account)
    provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "key"
    )
    assert_difference("Provider.count", -1) do
      delete provider_url(provider)
    end
    assert_redirected_to providers_url
  end
end
