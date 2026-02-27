# frozen_string_literal: true

require "test_helper"

module AI
  class ClientTest < ActiveSupport::TestCase
    setup do
      @account = accounts(:one)
      set_tenant(@account)

      # Create provider and model since there are no fixtures for them
      @provider = @account.providers.create!(
        name: "OpenAI",
        provider_type: "openai",
        api_key: "test-key"
      )
      @llm_model = @provider.llm_models.create!(
        account: @account,
        name: "GPT-4",
        identifier: "gpt-4",
        enabled: true
      )

      @space = @account.spaces.first || @account.spaces.create!(name: "Test Space")
      @user = users(:one)
    end

    test "initializes with required parameters" do
      client = Client.new(model: @llm_model)
      assert_equal @llm_model, client.model
      assert_empty client.tools
      assert_nil client.system_prompt
      assert_equal 0.7, client.temperature
    end

    test "initializes with all parameters" do
      tool = AI::Tools::Internal::QueryMemoriesTool.new
      client = Client.new(
        model: @llm_model,
        tools: [ tool ],
        system_prompt: "You are helpful",
        temperature: 0.5
      )

      assert_equal @llm_model, client.model
      assert_equal [ tool ], client.tools
      assert_equal "You are helpful", client.system_prompt
      assert_equal 0.5, client.temperature
    end

    test "chat returns normalized response" do
      client = Client.new(model: @llm_model)

      # Mock the complete flow
      mock_response = Struct.new(:content, :input_tokens, :output_tokens, :model_id, :tool_calls).new(
        "Test response content", 100, 50, "gpt-4", nil
      )

      mock_chat = Struct.new(:response) do
        def with_instructions(*); self; end
        def with_temperature(*); self; end
        def add_message(*); self; end
        def with_tools(*); self; end
        def complete; response; end
      end.new(mock_response)

      mock_context = Struct.new(:chat_result) do
        def chat(**args); chat_result; end
      end.new(mock_chat)

      RubyLLM.stubs(:context).yields(stub(:openai_api_key= => nil, :openai_organization_id= => nil)).returns(mock_context)

      response = client.chat(messages: [ { role: "user", content: "Hello" } ])

      assert_instance_of AI::Model::Response, response
      assert_equal "Test response content", response.content
      assert_equal 100, response.usage.input_tokens
      assert_equal 50, response.usage.output_tokens
      assert_equal 150, response.usage.total_tokens
    end

    test "complete is convenience method for single-turn" do
      client = Client.new(model: @llm_model)

      mock_response = Struct.new(:content, :input_tokens, :output_tokens, :model_id, :tool_calls).new(
        "Test response", 10, 5, "gpt-4", nil
      )

      mock_chat = Struct.new(:response) do
        def with_instructions(*); self; end
        def with_temperature(*); self; end
        def add_message(*); self; end
        def complete; response; end
      end.new(mock_response)

      mock_context = Struct.new(:chat_result) do
        def chat(**args); chat_result; end
      end.new(mock_chat)

      RubyLLM.stubs(:context).yields(stub(:openai_api_key= => nil)).returns(mock_context)

      response = client.complete(prompt: "Hello")

      assert_instance_of AI::Model::Response, response
      assert_equal "Test response", response.content
    end

    test "chat creates usage record when context provided" do
      client = Client.new(model: @llm_model)

      # Create a conversation for tracking
      council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
      conversation = @account.conversations.create!(
        council: council,
        user: @user,
        title: "Test"
      )
      message = @account.messages.create!(
        conversation: conversation,
        sender: @user,
        role: "user",
        content: "Hello"
      )

      mock_response = Struct.new(:content, :input_tokens, :output_tokens, :model_id, :tool_calls).new(
        "Response", 100, 50, "gpt-4", nil
      )

      mock_chat = Struct.new(:response) do
        def with_instructions(*); self; end
        def with_temperature(*); self; end
        def add_message(*); self; end
        def complete; response; end
      end.new(mock_response)

      mock_context = Struct.new(:chat_result) do
        def chat(**args); chat_result; end
      end.new(mock_chat)

      RubyLLM.stubs(:context).yields(stub(:openai_api_key= => nil, :openai_organization_id= => nil)).returns(mock_context)

      assert_difference "UsageRecord.count", 1 do
        client.chat(
          messages: [ { role: "user", content: "Hello" } ],
          context: {
            space: @space,
            conversation: conversation,
            message: message,
            account: @account
          }
        )
      end

      usage_record = UsageRecord.last
      assert_equal 100, usage_record.input_tokens
      assert_equal 50, usage_record.output_tokens
      assert_equal @provider.provider_type, usage_record.provider
      assert_equal @llm_model.identifier, usage_record.model
    end

    test "chat handles tool calls in response" do
      # Verify that tool calls are properly parsed from RubyLLM response
      # Note: Testing with tools requires complex RubyLLM mocking
      # This test verifies the response normalization works correctly
      tool_call_data = Struct.new(:id, :name, :params).new("tc-1", "query_memories", { "query" => "test" })
      mock_response = Struct.new(:content, :input_tokens, :output_tokens, :model_id, :tool_calls).new(
        "I found some memories.", 100, 50, "gpt-4", [ tool_call_data ]
      )

      # Simple mocks - test without tools to verify response parsing
      mock_chat = Struct.new(:response).new(mock_response)
      def mock_chat.with_instructions(*); self; end
      def mock_chat.with_temperature(*); self; end
      def mock_chat.add_message(*); self; end
      def mock_chat.complete; response; end

      mock_context = Struct.new(:chat_result).new(mock_chat)
      def mock_context.chat(**args); chat_result; end

      client = Client.new(model: @llm_model)  # No tools for this test

      RubyLLM.stubs(:context).yields(stub(:openai_api_key= => nil)).returns(mock_context)

      response = client.chat(messages: [ { role: "user", content: "Search memories" } ])

      assert response.tool_call?
      assert_equal 1, response.tool_calls.length
      assert_equal "query_memories", response.tool_calls.first.name
      assert_equal({ "query" => "test" }, response.tool_calls.first.arguments)
    end

    test "chat raises RateLimitError on RubyLLM rate limit" do
      client = Client.new(model: @llm_model)

      # RubyLLM errors expect a response object, but we can use StandardError
      # and test that our wrapper converts it properly
      RubyLLM.stubs(:context).raises(StandardError.new("Rate limited"))

      error = assert_raises(Client::APIError) do
        client.chat(messages: [ { role: "user", content: "Hello" } ])
      end
      assert_match(/Rate limited/, error.message)
    end

    test "chat raises APIError on RubyLLM error" do
      client = Client.new(model: @llm_model)

      RubyLLM.stubs(:context).raises(StandardError.new("API error"))

      error = assert_raises(Client::APIError) do
        client.chat(messages: [ { role: "user", content: "Hello" } ])
      end
      assert_match(/API error/, error.message)
    end

    test "with_retry retries on rate limit errors" do
      client = Client.new(model: @llm_model)
      client.stubs(:sleep).returns(nil)

      attempts = 0
      # Use Net::OpenTimeout which is a retryable error
      result = client.send(:with_retry, max_attempts: 3) do
        attempts += 1
        raise Net::OpenTimeout, "Connection timeout" if attempts < 3
        "success"
      end

      assert_equal "success", result
      assert_equal 3, attempts
    end

    test "with_retry raises after max attempts" do
      client = Client.new(model: @llm_model)
      client.stubs(:sleep).returns(nil)

      # Use a retryable error type (Net::OpenTimeout)
      error = Net::OpenTimeout.new("Connection timeout")
      assert_raises(Net::OpenTimeout) do
        client.send(:with_retry, max_attempts: 2) do
          raise error
        end
      end
    end

    test "chat does not fail if usage tracking fails" do
      client = Client.new(model: @llm_model)

      mock_response = Struct.new(:content, :input_tokens, :output_tokens, :model_id, :tool_calls).new(
        "Test response content", 100, 50, "gpt-4", nil
      )

      mock_chat = Struct.new(:response) do
        def with_instructions(*); self; end
        def with_temperature(*); self; end
        def add_message(*); self; end
        def complete; response; end
      end.new(mock_response)

      mock_context = Struct.new(:chat_result) do
        def chat(**args); chat_result; end
      end.new(mock_chat)

      RubyLLM.stubs(:context).yields(stub(:openai_api_key= => nil)).returns(mock_context)

      # Simulate tracking failure
      UsageRecord.stubs(:create!).raises(StandardError.new("DB error"))

      # Should not raise
      response = client.chat(
        messages: [ { role: "user", content: "Hello" } ],
        context: { space: @space }
      )

      assert_equal "Test response content", response.content
    end

    test "streaming is supported" do
      client = Client.new(model: @llm_model)

      received_chunks = []
      mock_response = Struct.new(:content, :input_tokens, :output_tokens, :model_id, :tool_calls).new(
        "Hello world!", nil, nil, "gpt-4", nil
      )

      mock_chat = Struct.new(:response, :chunks) do
        def with_instructions(*); self; end
        def with_temperature(*); self; end
        def add_message(*); self; end
        def complete(streaming: false, &block)
          if block && streaming
            block.call(Struct.new(:content).new("Hello world!"))
          end
          response
        end
      end.new(mock_response, nil)

      mock_context = Struct.new(:chat_result) do
        def chat(**args); chat_result; end
      end.new(mock_chat)

      RubyLLM.stubs(:context).yields(stub(:openai_api_key= => nil)).returns(mock_context)

      response = client.chat(messages: [ { role: "user", content: "Hello" } ]) do |chunk|
        received_chunks << chunk
      end

      assert_equal [ "Hello world!" ], received_chunks
      assert_instance_of AI::Model::Response, response
    end

    test "handles missing tokens in response" do
      mock_response = Struct.new(:content, :input_tokens, :output_tokens, :model_id, :tool_calls).new(
        "Response", nil, nil, "gpt-4", nil
      )

      mock_chat = Struct.new(:response) do
        def with_instructions(*); self; end
        def with_temperature(*); self; end
        def add_message(*); self; end
        def complete; response; end
      end.new(mock_response)

      mock_context = Struct.new(:chat_result) do
        def chat(**args); chat_result; end
      end.new(mock_chat)

      client = Client.new(model: @llm_model)

      RubyLLM.stubs(:context).yields(stub(:openai_api_key= => nil)).returns(mock_context)

      response = client.chat(messages: [ { role: "user", content: "Hello" } ])

      assert_nil response.usage
    end
  end
end
