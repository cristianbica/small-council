# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  class ModelInteractionRecorderTest < ActiveSupport::TestCase
    setup do
      @account = accounts(:one)
      set_tenant(@account)

      @space = @account.spaces.first || @account.spaces.create!(name: "Test Space")
      @user = users(:one)

      # Create provider and model
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

      # Create conversation infrastructure
      @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
      @conversation = @account.conversations.create!(council: @council, user: @user, title: "Test", space: @space)
      @message = @account.messages.create!(
        conversation: @conversation, sender: @user, role: "user", content: "Hello"
      )

      @recorder = AI::ModelInteractionRecorder.new(
        message_id: @message.id,
        account_id: @account.id
      )
    end

    # =========================================================================
    # Helpers
    # =========================================================================

    def build_mock_chat(messages: [], model_id: "gpt-4", provider: "openai", temperature: 0.7)
      mock_chat = Object.new
      mock_model = OpenStruct.new(id: model_id, provider: provider)
      mock_chat.define_singleton_method(:model) { mock_model }
      mock_chat.define_singleton_method(:messages) { messages }
      mock_chat.instance_variable_set(:@temperature, temperature)
      mock_chat
    end

    def build_mock_response(role: :assistant, content: "Hello!", input_tokens: 100, output_tokens: 50, model_id: "gpt-4")
      RubyLLM::Message.new(
        role: role,
        content: content,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        model_id: model_id
      )
    end

    def build_mock_tool_call(name: "query_memories", id: "tc-1", arguments: { "query" => "test" })
      OpenStruct.new(name: name, id: id, arguments: arguments)
    end

    # =========================================================================
    # Chat recording tests
    # =========================================================================

    test "records assistant response with correct fields" do
      response = build_mock_response
      chat = build_mock_chat(messages: [
        RubyLLM::Message.new(role: :user, content: "Hi"),
        response
      ])

      @recorder.start_timing

      assert_difference "ModelInteraction.count", 1 do
        @recorder.record_chat(chat: chat, response: response)
      end

      interaction = ModelInteraction.last
      assert_equal @message.id, interaction.message_id
      assert_equal @account.id, interaction.account_id
      assert_equal "chat", interaction.interaction_type
      assert_equal "gpt-4", interaction.model_identifier
      assert_equal 100, interaction.input_tokens
      assert_equal 50, interaction.output_tokens
      assert_not_nil interaction.duration_ms
      assert_equal 0, interaction.sequence
    end

    test "skips non-assistant messages from on_end_message" do
      response = build_mock_response(role: :tool, content: "tool result")
      chat = build_mock_chat(messages: [ response ])

      @recorder.start_timing

      assert_no_difference "ModelInteraction.count" do
        @recorder.record_chat(chat: chat, response: response)
      end
    end

    test "skips when message_id is nil" do
      recorder = AI::ModelInteractionRecorder.new(message_id: nil, account_id: @account.id)
      response = build_mock_response
      chat = build_mock_chat(messages: [ response ])

      recorder.start_timing

      assert_no_difference "ModelInteraction.count" do
        recorder.record_chat(chat: chat, response: response)
      end
    end

    test "skips when account_id is nil" do
      recorder = AI::ModelInteractionRecorder.new(message_id: @message.id, account_id: nil)
      response = build_mock_response
      chat = build_mock_chat(messages: [ response ])

      recorder.start_timing

      assert_no_difference "ModelInteraction.count" do
        recorder.record_chat(chat: chat, response: response)
      end
    end

    test "increments sequence for multiple interactions on same message" do
      response1 = build_mock_response(content: "First")
      response2 = build_mock_response(content: "Second")

      chat1 = build_mock_chat(messages: [
        RubyLLM::Message.new(role: :user, content: "Hi"),
        response1
      ])
      chat2 = build_mock_chat(messages: [
        RubyLLM::Message.new(role: :user, content: "Hi"),
        response1,
        response2
      ])

      @recorder.start_timing

      @recorder.record_chat(chat: chat1, response: response1)
      @recorder.record_chat(chat: chat2, response: response2)

      interactions = ModelInteraction.where(message_id: @message.id).chronological.to_a
      assert_equal 2, interactions.size
      assert_equal 0, interactions[0].sequence
      assert_equal 1, interactions[1].sequence
    end

    test "computes duration_ms from monotonic clock" do
      response = build_mock_response
      chat = build_mock_chat(messages: [ response ])

      @recorder.start_timing
      sleep 0.01
      @recorder.record_chat(chat: chat, response: response)

      interaction = ModelInteraction.last
      assert interaction.duration_ms > 0, "Expected duration_ms > 0, got #{interaction.duration_ms}"
    end

    test "does not raise on recording failure" do
      response = build_mock_response
      chat = build_mock_chat(messages: [ response ])

      @recorder.start_timing

      ModelInteraction.stubs(:create!).raises(StandardError.new("DB error"))

      assert_nothing_raised do
        @recorder.record_chat(chat: chat, response: response)
      end
    end

    test "builds correct request_payload with system prompt and messages" do
      system_msg = RubyLLM::Message.new(role: :system, content: "Be helpful")
      user_msg = RubyLLM::Message.new(role: :user, content: "Hello there")
      response = build_mock_response(content: "Hi!")

      chat = build_mock_chat(
        messages: [ system_msg, user_msg, response ],
        model_id: "gpt-4",
        provider: "openai",
        temperature: 0.7
      )

      @recorder.start_timing
      @recorder.record_chat(chat: chat, response: response)

      interaction = ModelInteraction.last
      payload = interaction.request_payload

      assert_equal "gpt-4", payload["model"]
      assert_equal "openai", payload["provider"]
      assert_equal 0.7, payload["temperature"]

      # System prompt
      assert_kind_of Array, payload["system_prompt"]
      assert_equal 1, payload["system_prompt"].size
      assert_equal "text", payload["system_prompt"][0]["type"]
      assert_equal "Be helpful", payload["system_prompt"][0]["content"]

      # Messages (non-system, excluding the response itself)
      assert_kind_of Array, payload["messages"]
      assert_equal 1, payload["messages"].size
      assert_equal "user", payload["messages"][0]["role"]
    end

    test "builds correct response_payload" do
      response = build_mock_response(content: "Hello!", input_tokens: 100, output_tokens: 50, model_id: "gpt-4")
      chat = build_mock_chat(messages: [ response ])

      @recorder.start_timing
      @recorder.record_chat(chat: chat, response: response)

      interaction = ModelInteraction.last
      payload = interaction.response_payload

      assert_kind_of Array, payload["messages"]
      assert_equal 1, payload["messages"].size
      assert_equal "assistant", payload["messages"][0]["role"]
      assert_equal 100, payload["input_tokens"]
      assert_equal 50, payload["output_tokens"]
      assert_equal "gpt-4", payload["model"]
    end

    test "resets timer after recording for next round-trip" do
      response1 = build_mock_response(content: "First")
      response2 = build_mock_response(content: "Second")

      chat1 = build_mock_chat(messages: [
        RubyLLM::Message.new(role: :user, content: "Hi"),
        response1
      ])

      @recorder.start_timing
      sleep 0.02
      @recorder.record_chat(chat: chat1, response: response1)

      first_duration = ModelInteraction.last.duration_ms

      # Second recording should measure from the reset point, not from the original start
      chat2 = build_mock_chat(messages: [
        RubyLLM::Message.new(role: :user, content: "Hi"),
        response1,
        response2
      ])
      sleep 0.01
      @recorder.record_chat(chat: chat2, response: response2)

      second_duration = ModelInteraction.last.duration_ms

      assert second_duration > 0, "Expected second duration > 0"
      assert first_duration > 0, "Expected first duration > 0"
      # The second should be shorter since timer was reset after the first (and we slept less)
      # Both should be non-cumulative
      assert second_duration < first_duration,
        "Expected second duration (#{second_duration}) < first duration (#{first_duration}) — timer should reset"
    end

    # =========================================================================
    # Tool recording tests
    # =========================================================================

    test "records tool call with name, arguments, and result" do
      tool_call = build_mock_tool_call(name: "query_memories", id: "tc-1", arguments: { "query" => "test" })

      @recorder.record_tool_call(tool_call)

      assert_difference "ModelInteraction.count", 1 do
        @recorder.record_tool_result("Found 3 results")
      end

      interaction = ModelInteraction.last
      assert_equal "tool", interaction.interaction_type
      assert_equal "query_memories", interaction.request_payload["tool_name"]
      assert_equal "tc-1", interaction.request_payload["tool_call_id"]
      assert_equal({ "query" => "test" }, interaction.request_payload["arguments"])
      assert_equal "query_memories", interaction.response_payload["tool_name"]
      assert_equal "Found 3 results", interaction.response_payload["result"]
    end

    test "records tool interaction_type as tool" do
      tool_call = build_mock_tool_call
      @recorder.record_tool_call(tool_call)
      @recorder.record_tool_result("result")

      interaction = ModelInteraction.last
      assert_equal "tool", interaction.interaction_type
    end

    test "computes tool duration_ms from call to result" do
      tool_call = build_mock_tool_call
      @recorder.record_tool_call(tool_call)
      sleep 0.01
      @recorder.record_tool_result("result")

      interaction = ModelInteraction.last
      assert interaction.duration_ms > 0, "Expected tool duration_ms > 0, got #{interaction.duration_ms}"
    end

    test "skips tool result when no pending tool call" do
      assert_no_difference "ModelInteraction.count" do
        @recorder.record_tool_result("orphan result")
      end
    end

    test "does not raise on tool recording failure" do
      tool_call = build_mock_tool_call
      @recorder.record_tool_call(tool_call)

      ModelInteraction.stubs(:create!).raises(StandardError.new("DB error"))

      assert_nothing_raised do
        @recorder.record_tool_result("result")
      end
    end

    test "clears pending tool call after recording" do
      tool_call = build_mock_tool_call
      @recorder.record_tool_call(tool_call)
      @recorder.record_tool_result("first result")

      # Second call to record_tool_result without a new record_tool_call should be a no-op
      assert_no_difference "ModelInteraction.count" do
        @recorder.record_tool_result("orphan result")
      end

      assert_equal 1, ModelInteraction.where(message_id: @message.id, interaction_type: "tool").count
    end

    # =========================================================================
    # Sequencing tests
    # =========================================================================

    test "sequences chat and tool interactions correctly across a tool-call loop" do
      # Simulate a full tool-call loop:
      # 1. LLM responds with a tool call → chat interaction (seq 0)
      # 2. Tool executes → tool interaction (seq 1)
      # 3. LLM responds with final answer → chat interaction (seq 2)

      tool_call_obj = RubyLLM::ToolCall.new(id: "tc-1", name: "query_memories", arguments: { "query" => "test" })

      # Step 1: Assistant response with tool calls
      assistant_with_tool = RubyLLM::Message.new(
        role: :assistant,
        content: "Let me search",
        input_tokens: 80,
        output_tokens: 20,
        model_id: "gpt-4",
        tool_calls: { "tc-1" => tool_call_obj }
      )

      chat1 = build_mock_chat(messages: [
        RubyLLM::Message.new(role: :user, content: "Search for test"),
        assistant_with_tool
      ])

      @recorder.start_timing
      @recorder.record_chat(chat: chat1, response: assistant_with_tool)

      # Step 2: Tool execution
      mock_tool_call = build_mock_tool_call(name: "query_memories", id: "tc-1", arguments: { "query" => "test" })
      @recorder.record_tool_call(mock_tool_call)
      @recorder.record_tool_result("Found 3 memories")

      # Step 3: Final assistant response
      final_response = build_mock_response(content: "Here are your results", input_tokens: 150, output_tokens: 60)

      chat3 = build_mock_chat(messages: [
        RubyLLM::Message.new(role: :user, content: "Search for test"),
        assistant_with_tool,
        RubyLLM::Message.new(role: :tool, content: "Found 3 memories"),
        final_response
      ])

      @recorder.record_chat(chat: chat3, response: final_response)

      # Verify
      interactions = ModelInteraction.where(message_id: @message.id).chronological.to_a
      assert_equal 3, interactions.size

      assert_equal 0, interactions[0].sequence
      assert_equal "chat", interactions[0].interaction_type

      assert_equal 1, interactions[1].sequence
      assert_equal "tool", interactions[1].interaction_type

      assert_equal 2, interactions[2].sequence
      assert_equal "chat", interactions[2].interaction_type
    end
  end
end
