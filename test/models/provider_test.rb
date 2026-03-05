require "test_helper"

class ProviderTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
  end

  test "valid provider with required fields" do
    provider = @account.providers.new(
      name: "OpenAI Production",
      provider_type: "openai",
      api_key: "sk-test123"
    )
    assert provider.valid?
  end

  test "requires name" do
    provider = @account.providers.new(provider_type: "openai")
    assert_not provider.valid?
    assert_includes provider.errors[:name], "can't be blank"
  end

  test "requires provider_type" do
    provider = @account.providers.new(name: "Test Provider")
    assert_not provider.valid?
    assert_includes provider.errors[:provider_type], "can't be blank"
  end

  test "requires unique name per account" do
    @account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "key1")
    duplicate = @account.providers.new(name: "OpenAI", provider_type: "openrouter", api_key: "key2")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "requires account" do
    ActsAsTenant.without_tenant do
      provider = Provider.new(
        name: "Test",
        provider_type: "openai",
        api_key: "key"
      )
      assert_not provider.valid?
      assert_includes provider.errors[:account], "can't be blank"
    end
  end

  test "encrypts credentials" do
    provider = @account.providers.create!(
      name: "Test",
      provider_type: "openai",
      api_key: "secret-key-123"
    )

    # Reload to ensure encryption round-trip
    provider.reload
    assert_equal "secret-key-123", provider.api_key
  end

  test "scopes enabled providers" do
    enabled = @account.providers.create!(name: "Enabled", provider_type: "openai", api_key: "key", enabled: true)
    disabled = @account.providers.create!(name: "Disabled", provider_type: "openai", api_key: "key", enabled: false)

    assert_includes Provider.enabled, enabled
    assert_not_includes Provider.enabled, disabled
  end

  test "scopes by_type" do
    openai = @account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "key")
    openrouter = @account.providers.create!(name: "OpenRouter", provider_type: "openrouter", api_key: "key")

    assert_includes Provider.by_type("openai"), openai
    assert_not_includes Provider.by_type("openai"), openrouter
  end

  test "has_many llm_models" do
    provider = @account.providers.create!(name: "Test", provider_type: "openai", api_key: "key")
    assert_respond_to provider, :llm_models
  end

  test "dependent destroy removes associated llm_models" do
    provider = @account.providers.create!(name: "Test", provider_type: "openai", api_key: "key")
    provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")

    assert_difference("LLMModel.count", -1) do
      provider.destroy
    end
  end

  test "provider_type enum values" do
    assert_includes Provider.provider_types.keys, "openai"
    assert_includes Provider.provider_types.keys, "openrouter"
  end

  test "type_openai? predicate method" do
    provider = @account.providers.create!(name: "Test", provider_type: "openai", api_key: "key")
    assert provider.type_openai?
    assert_not provider.type_openrouter?
  end

  test "api_key returns nil when credentials are nil" do
    provider = @account.providers.new(name: "No Creds", provider_type: "openai")
    # credentials is nil by default
    assert_nil provider.api_key
  end
end
