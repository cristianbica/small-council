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

  test "update renders edit on validation failure" do
    sign_in_as(@user)
    set_tenant(@account)
    provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "key"
    )

    patch provider_url(provider), params: { provider: { name: "" } }
    assert_response :unprocessable_entity
  end

  # ============================================================================
  # SECURITY TESTS - Added as part of security audit
  # ============================================================================

  test "cannot access provider from different account" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create provider in other account
    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Provider Account", slug: "other-provider-acct")
    end
    other_provider = ActsAsTenant.without_tenant do
      other_account.providers.create!(
        name: "Other Provider",
        provider_type: "openai",
        api_key: "secret-key"
      )
    end

    # Try to access other account's provider
    # The provider won't be found in Current.account.providers scope -> 404
    get edit_provider_url(other_provider)
    assert_response :not_found
  end

  test "cannot update provider from different account" do
    sign_in_as(@user)
    set_tenant(@account)

    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Provider Account", slug: "other-provider-update")
    end
    other_provider = ActsAsTenant.without_tenant do
      other_account.providers.create!(
        name: "Other Provider",
        provider_type: "openai",
        api_key: "secret-key"
      )
    end

    # Try to update other account's provider
    # The provider won't be found in Current.account.providers scope -> 404
    patch provider_url(other_provider), params: {
      provider: { name: "Hacked Name" }
    }
    assert_response :not_found

    # Verify name wasn't changed
    ActsAsTenant.without_tenant do
      assert_equal "Other Provider", other_provider.reload.name
    end
  end

  test "cannot destroy provider from different account" do
    sign_in_as(@user)
    set_tenant(@account)

    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Provider Account", slug: "other-provider-destroy")
    end
    other_provider = ActsAsTenant.without_tenant do
      other_account.providers.create!(
        name: "Other Provider",
        provider_type: "openai",
        api_key: "secret-key"
      )
    end

    # Try to destroy other account's provider
    # The provider won't be found in Current.account.providers scope -> 404
    delete provider_url(other_provider)
    assert_response :not_found

    # Verify provider still exists
    ActsAsTenant.without_tenant do
      assert other_account.providers.exists?(other_provider.id)
    end
  end

  test "cannot manipulate account_id via provider form" do
    sign_in_as(@user)
    set_tenant(@account)

    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Mass Assign Provider", slug: "mass-assign-provider")
    end

    assert_difference("Provider.count") do
      post providers_url, params: {
        provider: {
          name: "Test Provider",
          provider_type: "openai",
          api_key: "test-key",
          account_id: other_account.id  # Attempting to set account
        }
      }
    end

    provider = Provider.last
    # Should be assigned to current user's account
    assert_equal @account.id, provider.account_id
    refute_equal other_account.id, provider.account_id
  end

  test "index only shows providers from current account" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create providers in different accounts
    @account.providers.create!(name: "My Provider", provider_type: "openai", api_key: "key1")

    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Index", slug: "other-index")
    end
    ActsAsTenant.without_tenant do
      other_account.providers.create!(name: "Other Provider", provider_type: "openai", api_key: "key2")
    end

    get providers_url
    assert_response :success
    # View uses h3 for provider names in cards
    assert_select "h3", text: /My Provider/
    assert_select "h3", { text: /Other Provider/, count: 0 }
  end

  test "provider_type is immutable and cannot be changed on update" do
    sign_in_as(@user)
    set_tenant(@account)

    provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "key"
    )

    # Attempt to change provider_type to anthropic
    patch provider_url(provider), params: {
      provider: {
        name: "Updated Name",
        provider_type: "anthropic"  # Should be ignored
      }
    }

    assert_redirected_to providers_url

    provider.reload
    assert_equal "Updated Name", provider.name  # Name changed
    assert_equal "openai", provider.provider_type  # Type unchanged
  end
end
