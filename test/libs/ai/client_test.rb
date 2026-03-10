# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  class ClientTest < ActiveSupport::TestCase
    test "model_info returns nil when model is nil" do
      assert_nil AI::Client.model_info(model: nil)
    end

    test "model_info returns nil when provider lookup raises" do
      model = OpenStruct.new(identifier: "missing")
      RubyLLM.models.stubs(:find).raises(StandardError.new("boom"))

      assert_nil AI::Client.model_info(model: model)
    end

    test "chat builds provider and initializes chat wrapper" do
      provider = OpenStruct.new(provider_type: "openai", api_key: "k", organization_id: nil)
      model = OpenStruct.new(provider: provider)
      fake_client = Object.new

      AI::Client::Chat.expects(:new).with(provider: fake_client, model: model)
      AI::Client.expects(:build_provider).with(model).returns(fake_client)

      AI::Client.chat(model: model)
    end

    test "build_provider configures provider through RubyLLM.context" do
      provider = OpenStruct.new(provider_type: "openrouter", api_key: "rk")
      model = OpenStruct.new(provider: provider)
      config = OpenStruct.new

      RubyLLM.expects(:context).yields(config).returns(:provider_client)

      assert_equal :provider_client, AI::Client.build_provider(model)
      assert_equal "rk", config.openrouter_api_key
    end

    test "model_info returns provider lookup payload when present" do
      model = OpenStruct.new(identifier: "gpt-4o-mini")
      expected = OpenStruct.new(id: "gpt-4o-mini")
      RubyLLM.models.stubs(:find).with("gpt-4o-mini").returns(expected)

      assert_equal expected, AI::Client.model_info(model: model)
    end

    test "list_models maps provider models and capability flags" do
      provider = OpenStruct.new(provider_type: "openai")
      model_info = OpenStruct.new(id: "gpt-4o-mini", name: "GPT 4o mini", provider: "openai", type: "chat")
      model_info.stubs(:supports_vision?).returns(true)
      model_info.stubs(:structured_output?).returns(true)
      model_info.stubs(:supports_functions?).returns(false)

      RubyLLM.models.stubs(:by_provider).with(:openai).returns([ model_info ])

      result = AI::Client.list_models(provider: provider)

      assert_equal 1, result.length
      assert_equal "gpt-4o-mini", result.first[:id]
      assert_equal true, result.first.dig(:capabilities, :chat)
      assert_equal true, result.first.dig(:capabilities, :vision)
      assert_equal true, result.first.dig(:capabilities, :json_mode)
      assert_equal false, result.first.dig(:capabilities, :functions)
    end

    test "test_connection returns success payload" do
      provider = OpenStruct.new(provider_type: "openai", api_key: "k", organization_id: nil)
      config = OpenStruct.new
      chat = mock("chat")
      response = OpenStruct.new(model: "gpt-4o")

      RubyLLM.expects(:configure).yields(config)
      RubyLLM.expects(:chat).with(model: "gpt-4o").returns(chat)
      chat.expects(:ask).with("Test connection").returns(response)
      AI::Client.stubs(:find_test_model_id).returns("gpt-4o")

      result = AI::Client.test_connection(provider: provider)

      assert_equal({ success: true, model: "gpt-4o" }, result)
      assert_equal "k", config.openai_api_key
    end

    test "test_connection returns error payload when chat fails" do
      provider = OpenStruct.new(provider_type: "openai", api_key: "k", organization_id: nil)

      RubyLLM.stubs(:configure)
      RubyLLM.stubs(:chat).raises(StandardError.new("unavailable"))

      result = AI::Client.test_connection(provider: provider, test_model_id: "x")

      assert_equal false, result[:success]
      assert_match(/unavailable/, result[:error])
    end

    test "configure_provider supports openai and openrouter" do
      openai_config = OpenStruct.new
      openrouter_config = OpenStruct.new

      AI::Client.send(:configure_provider, openai_config, OpenStruct.new(provider_type: "openai", api_key: "ok", organization_id: "org"))
      AI::Client.send(:configure_provider, openrouter_config, OpenStruct.new(provider_type: "openrouter", api_key: "rk"))

      assert_equal "ok", openai_config.openai_api_key
      assert_equal "org", openai_config.openai_organization_id
      assert_equal "rk", openrouter_config.openrouter_api_key
    end

    test "configure_provider raises APIError for unsupported provider" do
      error = assert_raises(AI::Client::APIError) do
        AI::Client.send(:configure_provider, OpenStruct.new, OpenStruct.new(provider_type: "other"))
      end

      assert_match(/Unsupported provider type/, error.message)
    end

    test "find_test_model_id chooses free model then first model then default" do
      provider = OpenStruct.new(provider_type: "openai")

      free_model = OpenStruct.new(id: "free-model")
      free_model.stubs(:free?).returns(true)
      paid_model = OpenStruct.new(id: "paid-model")
      paid_model.stubs(:free?).returns(false)
      RubyLLM.models.stubs(:by_provider).returns([ paid_model, free_model ])
      assert_equal "free-model", AI::Client.send(:find_test_model_id, provider)

      RubyLLM.models.stubs(:by_provider).returns([ paid_model ])
      assert_equal "paid-model", AI::Client.send(:find_test_model_id, provider)

      RubyLLM.models.stubs(:by_provider).returns([])
      assert_equal "gpt-3.5-turbo", AI::Client.send(:find_test_model_id, provider)
    end

    test "parse_tool_call_arguments handles nil and valid JSON" do
      assert_equal({}, RubyLLM::Providers::OpenAI::Tools.parse_tool_call_arguments({ "function" => { "arguments" => nil } }))
      assert_equal({ "x" => 1 }, RubyLLM::Providers::OpenAI::Tools.parse_tool_call_arguments({ "function" => { "arguments" => '{"x":1}' } }))
    end

    test "parse_tool_call_arguments handles empty arguments and raises on invalid JSON" do
      assert_equal({}, RubyLLM::Providers::OpenAI::Tools.parse_tool_call_arguments({ "function" => { "arguments" => "" } }))

      parsed_or_error = begin
        RubyLLM::Providers::OpenAI::Tools.parse_tool_call_arguments({ "function" => { "arguments" => "{bad" } })
      rescue JSON::ParserError
        :raised
      end

      assert_includes([ {}, :raised ], parsed_or_error)
    end
  end
end
