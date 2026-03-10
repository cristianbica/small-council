# frozen_string_literal: true

require "test_helper"

class AI::ModelManagerTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @provider = @account.providers.create!(
      name: "ModelManager Test Provider",
      provider_type: "openai",
      api_key: "test-key",
      enabled: true
    )
  end

  # available_models tests
  test "available_models returns empty array when no enabled providers" do
    @provider.update!(enabled: false)
    result = AI::ModelManager.available_models(@account)
    # No enabled providers means no models from this provider
    assert result.none? { |m| m.provider == @provider }
  end

  test "available_models returns model infos for enabled provider" do
    AI::Client.stubs(:list_models).returns([
      { id: "gpt-4", name: "GPT-4", provider: "openai", capabilities: {} },
      { id: "gpt-3.5-turbo", name: "GPT-3.5", provider: "openai", capabilities: {} }
    ])

    results = AI::ModelManager.available_models(@account)
    provider_results = results.select { |m| m.provider == @provider }
    assert_equal 2, provider_results.count
    assert_equal "gpt-4", provider_results.first.model_id
    assert_equal "GPT-4", provider_results.first.name
  end

  test "available_models sets enabled false when LLMModel not found for model_id" do
    AI::Client.stubs(:list_models).returns([
      { id: "unknown-model", name: "Unknown", provider: "openai", capabilities: {} }
    ])

    results = AI::ModelManager.available_models(@account)
    provider_results = results.select { |m| m.provider == @provider }
    assert_equal false, provider_results.first.enabled
  end

  test "available_models sets enabled true when LLMModel exists and is enabled" do
    llm_model = @provider.llm_models.create!(
      account: @account, name: "GPT-4", identifier: "gpt-4", enabled: true
    )
    AI::Client.stubs(:list_models).returns([
      { id: "gpt-4", name: "GPT-4", provider: "openai", capabilities: {} }
    ])

    results = AI::ModelManager.available_models(@account)
    provider_results = results.select { |m| m.provider == @provider }
    assert_equal true, provider_results.first.enabled
    assert_equal llm_model, provider_results.first.llm_model
  end

  # enable_model tests
  test "enable_model creates new record when model does not exist" do
    AI::Client.stubs(:model_info).returns(nil)

    assert_difference "LLMModel.count", 1 do
      result = AI::ModelManager.enable_model(@account, @provider, "new-model")
      assert result.enabled
      assert_equal "new-model", result.identifier
    end
  end

  test "enable_model updates existing record if already exists" do
    existing = @provider.llm_models.create!(
      account: @account, name: "Old Name", identifier: "gpt-4", enabled: false
    )
    AI::Client.stubs(:model_info).returns(nil)

    assert_no_difference "LLMModel.count" do
      result = AI::ModelManager.enable_model(@account, @provider, "gpt-4")
      assert result.enabled
      assert_equal existing.id, result.id
    end
  end

  test "enable_model uses model_id as name fallback when api.info is nil" do
    AI::Client.stubs(:model_info).returns(nil)

    result = AI::ModelManager.enable_model(@account, @provider, "openai/gpt-4-turbo")
    # Falls back to last part of model_id after split("/")
    assert_equal "gpt-4-turbo", result.name
  end

  test "enable_model stores full metadata when api.info returns data" do
    mock_info = mock("model_info")
    mock_info.stubs(:name).returns("GPT-4 Turbo")
    mock_info.stubs(:as_json).returns({
      "type" => "chat",
      "context_window" => 128000,
      "vision" => true,
      "supports_functions" => true,
      "streaming" => true,
      "structured_output" => false,
      "pricing" => { "input" => 0.01, "output" => 0.03 }
    })
    AI::Client.stubs(:model_info).returns(mock_info)

    result = AI::ModelManager.enable_model(@account, @provider, "gpt-4-turbo-full")
    assert_equal "GPT-4 Turbo", result.name
    assert_equal 128000, result.context_window
    assert_equal false, result.free
  end

  test "enable_model sets free to true when both input and output prices are 0.0" do
    mock_info = mock("model_info")
    mock_info.stubs(:name).returns("Free Model")
    mock_info.stubs(:as_json).returns({
      "type" => "chat",
      "context_window" => 4096,
      "pricing" => { "input" => 0.0, "output" => 0.0 }
    })
    AI::Client.stubs(:model_info).returns(mock_info)

    result = AI::ModelManager.enable_model(@account, @provider, "free-model-id")
    assert result.free
  end

  # disable_model tests
  test "disable_model returns nil when model not found" do
    result = AI::ModelManager.disable_model(@account, @provider, "nonexistent-model")
    assert_nil result
  end

  test "disable_model sets enabled to false when model found" do
    existing = @provider.llm_models.create!(
      account: @account, name: "Active Model", identifier: "active-model", enabled: true
    )

    result = AI::ModelManager.disable_model(@account, @provider, "active-model")
    assert_not_nil result
    assert_equal false, result.enabled
    assert_equal false, existing.reload.enabled
  end
end
