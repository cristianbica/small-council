require "test_helper"

module LLM
  class ModelManagerTest < ActiveSupport::TestCase
    setup do
      @account = accounts(:one)
      set_tenant(@account)
      @provider = @account.providers.create!(
        name: "OpenAI",
        provider_type: "openai",
        api_key: "test-key"
      )
    end

    test "available_models returns empty array when no providers enabled" do
      @provider.update!(enabled: false)
      models = LLM::ModelManager.available_models(@account)
      assert_empty models
    end

    test "available_models returns ModelInfo structs for enabled providers" do
      # Mock the provider's API to return model list
      mock_client = mock("client")
      mock_client.expects(:list_models).returns([
        { id: "gpt-4", name: "GPT-4", capabilities: { chat: true, vision: true } },
        { id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", capabilities: { chat: true } }
      ])

      Provider.any_instance.stubs(:api).returns(mock_client)

      models = LLM::ModelManager.available_models(@account)

      assert_equal 2, models.length
      assert models.all? { |m| m.is_a?(LLM::ModelManager::ModelInfo) }
      assert_equal "gpt-4", models.first.model_id
      assert_equal "GPT-4", models.first.name
    end

    test "available_models includes enabled status from existing LLMModel records" do
      # Create an enabled model
      @provider.llm_models.create!(
        account: @account,
        name: "GPT-4",
        identifier: "gpt-4",
        enabled: true
      )

      mock_client = mock("client")
      mock_client.expects(:list_models).returns([
        { id: "gpt-4", name: "GPT-4", capabilities: { chat: true } }
      ])

      Provider.any_instance.stubs(:api).returns(mock_client)

      models = LLM::ModelManager.available_models(@account)

      assert_equal 1, models.length
      assert models.first.enabled
      assert models.first.llm_model.present?
    end

    test "enable_model creates new LLMModel with metadata" do
      mock_client = mock("client")
      mock_info = mock("model_info")
      mock_info.stubs(:name).returns("GPT-4 Turbo")
      mock_info.stubs(:type).returns("chat")
      mock_info.stubs(:supports_vision?).returns(true)
      mock_info.stubs(:structured_output?).returns(true)
      mock_info.stubs(:supports_functions?).returns(true)
      mock_info.stubs(:input_price_per_million).returns(10.0)
      mock_info.stubs(:output_price_per_million).returns(30.0)
      mock_info.stubs(:context_window).returns(128000)
      mock_info.stubs(:max_tokens).returns(4096)

      LLM::Client.any_instance.stubs(:info).returns(mock_info)

      assert_difference("LLMModel.count") do
        llm_model = LLM::ModelManager.enable_model(@account, @provider, "gpt-4-turbo")

        assert_equal "GPT-4 Turbo", llm_model.name
        assert_equal "gpt-4-turbo", llm_model.identifier
        assert llm_model.enabled
        assert_equal true, llm_model.metadata["capabilities"]["chat"]
        assert_equal true, llm_model.metadata["capabilities"]["vision"]
        assert_equal 10.0, llm_model.metadata["pricing"]["input_price_per_million"]
        assert_equal 128000, llm_model.metadata["context_window"]
      end
    end

    test "enable_model updates existing LLMModel" do
      existing = @provider.llm_models.create!(
        account: @account,
        name: "Old Name",
        identifier: "gpt-4",
        enabled: false
      )

      mock_info = mock("model_info")
      mock_info.stubs(:name).returns("GPT-4 Updated")
      mock_info.stubs(:type).returns("chat")
      mock_info.stubs(:supports_vision?).returns(false)
      mock_info.stubs(:structured_output?).returns(false)
      mock_info.stubs(:supports_functions?).returns(false)
      mock_info.stubs(:input_price_per_million).returns(5.0)
      mock_info.stubs(:output_price_per_million).returns(15.0)
      mock_info.stubs(:context_window).returns(8192)
      mock_info.stubs(:max_tokens).returns(2048)

      LLM::Client.any_instance.stubs(:info).returns(mock_info)

      assert_no_difference("LLMModel.count") do
        llm_model = LLM::ModelManager.enable_model(@account, @provider, "gpt-4")

        assert_equal existing.id, llm_model.id
        assert_equal "GPT-4 Updated", llm_model.name
        assert llm_model.enabled
      end
    end

    test "enable_model falls back to model_id when ruby_llm has no info" do
      LLM::Client.any_instance.stubs(:info).returns(nil)

      assert_difference("LLMModel.count") do
        llm_model = LLM::ModelManager.enable_model(@account, @provider, "openai/custom-model")

        assert_equal "custom-model", llm_model.name
        assert_equal "openai/custom-model", llm_model.identifier
        assert llm_model.enabled
      end
    end

    test "disable_model sets enabled to false" do
      llm_model = @provider.llm_models.create!(
        account: @account,
        name: "GPT-4",
        identifier: "gpt-4",
        enabled: true
      )

      result = LLM::ModelManager.disable_model(@account, @provider, "gpt-4")

      assert_equal llm_model, result
      assert_not result.enabled
    end

    test "disable_model returns nil when model not found" do
      result = LLM::ModelManager.disable_model(@account, @provider, "nonexistent-model")
      assert_nil result
    end

    test "ModelInfo struct has all required attributes" do
      model_info = LLM::ModelManager::ModelInfo.new(
        provider: @provider,
        model_id: "test-model",
        name: "Test Model",
        enabled: true,
        llm_model: nil,
        capabilities: { chat: true }
      )

      assert_equal @provider, model_info.provider
      assert_equal "test-model", model_info.model_id
      assert_equal "Test Model", model_info.name
      assert model_info.enabled
      assert_equal({ chat: true }, model_info.capabilities)
    end
  end
end
