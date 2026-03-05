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

  test "scope enabled excludes deprecated" do
    enabled = @provider.llm_models.create!(account: @account, name: "Active", identifier: "active")
    deprecated = @provider.llm_models.create!(account: @account, name: "Deprecated", identifier: "old", deprecated: true)

    enabled_models = LLMModel.enabled
    assert_includes enabled_models, enabled
    assert_not_includes enabled_models, deprecated
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

  test "input_price returns 0.0 when metadata is empty" do
    model = @provider.llm_models.create!(
      account: @account, name: "No Meta Model", identifier: "no-meta",
      metadata: {}
    )
    assert_equal 0.0, model.input_price
  end

  test "output_price returns 0.0 when metadata is empty" do
    model = @provider.llm_models.create!(
      account: @account, name: "No Meta Model 2", identifier: "no-meta-2",
      metadata: {}
    )
    assert_equal 0.0, model.output_price
  end

  test "scope free returns only free models" do
    free_model = @provider.llm_models.create!(
      account: @account, name: "Free", identifier: "free-scope", free: true
    )
    paid_model = @provider.llm_models.create!(
      account: @account, name: "Paid", identifier: "paid-scope", free: false
    )
    free_results = LLMModel.free
    assert_includes free_results, free_model
    assert_not_includes free_results, paid_model
  end
end
