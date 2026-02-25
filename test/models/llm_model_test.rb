require "test_helper"

class LLMModelTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @provider = @account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "key")
  end

  test "valid llm_model with required fields" do
    model = @provider.llm_models.new(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )
    assert model.valid?
  end

  test "requires name" do
    model = @provider.llm_models.new(account: @account, identifier: "gpt-4")
    assert_not model.valid?
    assert_includes model.errors[:name], "can't be blank"
  end

  test "requires identifier" do
    model = @provider.llm_models.new(account: @account, name: "GPT-4")
    assert_not model.valid?
    assert_includes model.errors[:identifier], "can't be blank"
  end

  test "requires identifier unique per provider" do
    @provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    duplicate = @provider.llm_models.new(account: @account, name: "GPT-4 Turbo", identifier: "gpt-4")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:identifier], "has already been taken"
  end

  test "requires provider" do
    model = LLMModel.new(account: @account, name: "GPT-4", identifier: "gpt-4")
    assert_not model.valid?
    assert_includes model.errors[:provider], "can't be blank"
  end

  test "requires account via acts_as_tenant" do
    # acts_as_tenant automatically sets account, so we verify the association exists
    model = @provider.llm_models.new(account: @account, name: "GPT-4", identifier: "gpt-4")
    assert_equal @account, model.account
    assert model.valid?
  end

  test "soft delete sets deleted_at" do
    model = @provider.llm_models.create!(account: @account, name: "Old Model", identifier: "old")
    model.soft_delete
    assert model.deleted?
    assert model.deleted_at.present?
  end

  test "scope available excludes deprecated and deleted" do
    available = @provider.llm_models.create!(account: @account, name: "Active", identifier: "active")
    deprecated = @provider.llm_models.create!(account: @account, name: "Deprecated", identifier: "old", deprecated: true)
    deleted = @provider.llm_models.create!(account: @account, name: "Deleted", identifier: "gone")
    deleted.soft_delete

    available_models = LLMModel.available
    assert_includes available_models, available
    assert_not_includes available_models, deprecated
    assert_not_includes available_models, deleted
  end

  test "scope enabled excludes deprecated" do
    enabled = @provider.llm_models.create!(account: @account, name: "Active", identifier: "active")
    deprecated = @provider.llm_models.create!(account: @account, name: "Deprecated", identifier: "old", deprecated: true)

    enabled_models = LLMModel.enabled
    assert_includes enabled_models, enabled
    assert_not_includes enabled_models, deprecated
  end

  test "full_identifier returns provider/type format" do
    model = @provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    assert_equal "openai/gpt-4", model.full_identifier
  end

  test "display_name includes provider name" do
    model = @provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    assert_equal "GPT-4 (OpenAI)", model.display_name
  end

  test "belongs to provider" do
    model = LLMModel.new
    assert_respond_to model, :provider
  end

  test "has_many advisors" do
    model = LLMModel.new
    assert_respond_to model, :advisors
  end

  test "dependent nullify on advisors" do
    model = @provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    space = @account.spaces.create!(name: "Test Space")
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: model,
      space: space
    )

    model.destroy
    advisor.reload
    assert_nil advisor.llm_model_id
  end
end
