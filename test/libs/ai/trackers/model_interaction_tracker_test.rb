# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  module Trackers
    class ModelInteractionTrackerTest < ActiveSupport::TestCase
      class FakeChat
        attr_reader :messages, :model, :tools

        def initialize(messages:, model:, tools: [])
          @messages = messages
          @model = model
          @tools = tools
          @before_message_callbacks = []
          @after_message_callbacks = []
          @before_tool_call_callbacks = []
          @after_tool_call_callbacks = []
          @pending_tool_call = nil
        end

        def before_message(&block)
          @before_message_callbacks << block
          self
        end

        def after_message(&block)
          @after_message_callbacks << block
          self
        end

        def before_tool_call(&block)
          @before_tool_call_callbacks << block
          self
        end

        def after_tool_call(&block)
          @after_tool_call_callbacks << block
          self
        end

        def trigger_before_message
          @before_message_callbacks.each(&:call)
        end

        def trigger_after_message(response)
          @after_message_callbacks.each { |cb| cb.call(response) }
        end

        def trigger_before_tool_call(tool_call)
          @pending_tool_call = tool_call
          @before_tool_call_callbacks.each { |cb| cb.call(tool_call) }
        end

        def trigger_after_tool_result(result)
          tool_call = @pending_tool_call
          @pending_tool_call = nil
          @after_tool_call_callbacks.each { |cb| cb.call(tool_call, result) } if tool_call
        end
      end

      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @message = messages(:one)
        @context = { account: @account, message: @message }
      end

      test "register hooks callbacks and records chat/tool interactions" do
        request_system = OpenStruct.new(role: :system, content: "sys")
        request_user = OpenStruct.new(role: :user, content: "hello")
        response = OpenStruct.new(
          role: :assistant,
          content: "answer",
          input_tokens: 7,
          output_tokens: 9,
          model_id: "gpt-4o"
        )
        model = OpenStruct.new(id: "gpt-4o", provider: "openai")
        chat = FakeChat.new(messages: [ request_system, request_user, response ], model: model, tools: [ { name: "lookup" } ])

        tracker = ModelInteractionTracker.new(context: @context)

        assert_difference "ModelInteraction.count", 2 do
          tracker.register(chat)
          chat.trigger_before_message
          chat.trigger_after_message(response)
          chat.trigger_before_tool_call(OpenStruct.new(name: "lookup", id: "call_1", arguments: { q: "x" }))
          chat.trigger_after_tool_result({ ok: true })
        end

        records = ModelInteraction.where(message: @message).order(:sequence)
        assert_equal [ "chat", "tool" ], records.pluck(:interaction_type)
        assert_equal 7, records.first.input_tokens
        assert_equal 9, records.first.output_tokens
        assert_equal "gpt-4o", records.first.model_identifier
        assert_equal "lookup", records.second.request_payload["tool_name"]
        assert_equal "call_1", records.second.request_payload["tool_call_id"]

        @message.reload
        assert_equal 2, @message.tool_calls.size
        assert_equal "tool_call", @message.tool_calls.first["type"]
        assert_equal "tool_result", @message.tool_calls.second["type"]
      end

      test "register does nothing when context is not recordable" do
        chat = FakeChat.new(messages: [], model: OpenStruct.new(id: "gpt-4o", provider: "openai"))
        tracker = ModelInteractionTracker.new(context: {})

        assert_no_difference "ModelInteraction.count" do
          tracker.register(chat)
          chat.trigger_before_message
          chat.trigger_after_message(OpenStruct.new(role: :assistant, content: "x"))
        end
      end

      test "chat recording ignores non assistant responses" do
        response = OpenStruct.new(role: :user, content: "not assistant")
        chat = FakeChat.new(messages: [ response ], model: OpenStruct.new(id: "gpt-4o", provider: "openai"))
        tracker = ModelInteractionTracker.new(context: @context)

        assert_no_difference "ModelInteraction.count" do
          tracker.register(chat)
          chat.trigger_before_message
          chat.trigger_after_message(response)
        end
      end

      test "chat request payload falls back when raw body is invalid json" do
        raw = OpenStruct.new(env: OpenStruct.new(request_body: "{not-json"))
        response = OpenStruct.new(role: :assistant, content: "ok", raw: raw, input_tokens: 1, output_tokens: 1, model_id: "gpt")
        chat = FakeChat.new(messages: [ response ], model: OpenStruct.new(id: "gpt", provider: "openai"), tools: [ :a ])
        tracker = ModelInteractionTracker.new(context: @context)

        assert_difference "ModelInteraction.count", 1 do
          tracker.register(chat)
          chat.trigger_before_message
          chat.trigger_after_message(response)
        end

        payload = ModelInteraction.order(:id).last.request_payload
        assert_equal "gpt", payload["model"]
        assert_equal "openai", payload["provider"]
      end

      test "tool result is ignored when no pending call exists" do
        tracker = ModelInteractionTracker.new(context: @context)
        chat = FakeChat.new(messages: [], model: OpenStruct.new(id: "gpt", provider: "openai"))

        assert_no_difference "ModelInteraction.count" do
          tracker.register(chat)
          chat.trigger_after_tool_result("orphan")
        end
      end

      test "build_chat_request_payload returns parsed raw request body when valid" do
        raw = OpenStruct.new(env: OpenStruct.new(request_body: '{"messages":[{"role":"user"}]}'))
        response = OpenStruct.new(role: :assistant, content: "ok", raw: raw)
        chat = FakeChat.new(messages: [ response ], model: OpenStruct.new(id: "gpt", provider: "openai"))
        tracker = ModelInteractionTracker.new(context: @context)

        payload = tracker.send(:build_chat_request_payload, chat, response)

        assert_equal [ { "role" => "user" } ], payload["messages"]
      end

      test "build_chat_request_payload handles chat without messages and no tools method" do
        chat = Object.new
        chat.define_singleton_method(:model) { OpenStruct.new(id: "gpt", provider: "openai") }
        response = OpenStruct.new(role: :assistant, content: "ok")
        tracker = ModelInteractionTracker.new(context: @context)

        payload = tracker.send(:build_chat_request_payload, chat, response)

        assert_equal "gpt", payload[:model]
        assert_equal "openai", payload[:provider]
        assert_equal [], payload[:tools]
      end

      test "serialize_tools returns array fallback and rescue fallback" do
        tracker = ModelInteractionTracker.new(context: @context)

        simple_chat = OpenStruct.new(tools: :single_tool)
        assert_equal "single_tool", tracker.send(:serialize_tools, simple_chat)

        bad_tools = Object.new
        bad_tools.define_singleton_method(:as_json) { raise StandardError, "boom" }
        failing_chat = OpenStruct.new(tools: bad_tools)
        assert_equal [], tracker.send(:serialize_tools, failing_chat)
      end

      test "format_message includes tool calls and tool_call_id" do
        tool_call = OpenStruct.new(id: "tc_1", name: "lookup", arguments: { q: "x" })
        message = OpenStruct.new(
          role: :assistant,
          content: "hello",
          tool_calls: { "tc_1" => tool_call },
          tool_call_id: "tc_1"
        )

        tracker = ModelInteractionTracker.new(context: @context)
        formatted = tracker.send(:format_message, message)

        assert_equal "assistant", formatted[:role]
        assert_equal "tc_1", formatted[:tool_call_id]
        assert_equal 2, formatted[:parts].size
        assert_equal "tool_call", formatted[:parts].last[:type]
      end

      test "normalize_payload rescues when as_json raises" do
        bad_value = Object.new
        bad_value.define_singleton_method(:as_json) { raise StandardError, "bad" }
        bad_value.define_singleton_method(:to_s) { "fallback-value" }

        tracker = ModelInteractionTracker.new(context: @context)
        assert_equal "fallback-value", tracker.send(:normalize_payload, bad_value)
      end

      test "context_value supports method key string key and fallback index access" do
        tracker = ModelInteractionTracker.new(context: OpenStruct.new(message: @message, account: @account))
        assert_equal @message.id, tracker.send(:message_id)

        hash_tracker = ModelInteractionTracker.new(context: { "message" => @message, "account" => @account })
        assert_equal @account.id, hash_tracker.send(:account_id)

        message = @message
        index_only = Object.new
        index_only.define_singleton_method(:[]) do |key|
          return message if key == :message || key == "message"
          nil
        end
        tracker_with_index_only = ModelInteractionTracker.new(context: index_only)
        assert_equal @message.id, tracker_with_index_only.send(:message_id)
      end

      test "record_chat logs and continues when interaction creation fails" do
        response = OpenStruct.new(role: :assistant, content: "answer", input_tokens: 1, output_tokens: 2, model_id: "gpt")
        chat = FakeChat.new(messages: [ response ], model: OpenStruct.new(id: "gpt", provider: "openai"))
        tracker = ModelInteractionTracker.new(context: @context)

        tracker.stubs(:create_interaction!).raises(StandardError.new("db fail"))
        Rails.logger.expects(:error).with(regexp_matches(/Failed to record chat/))

        tracker.register(chat)
        chat.trigger_before_message
        chat.trigger_after_message(response)
      end

      test "record_tool_result logs on interaction failure" do
        tracker = ModelInteractionTracker.new(context: @context)
        chat = FakeChat.new(messages: [], model: OpenStruct.new(id: "gpt", provider: "openai"))

        tracker.register(chat)
        chat.trigger_before_tool_call(OpenStruct.new(name: "lookup", id: "tool_1", arguments: { q: "x" }))

        tracker.stubs(:create_interaction!).raises(StandardError.new("write fail"))
        Rails.logger.expects(:error).with(regexp_matches(/Failed to record tool/))

        chat.trigger_after_tool_result({ ok: true })
      end

      test "persist_tool_trace logs when message update fails" do
        failing_message = Object.new
        failing_message.define_singleton_method(:id) { 123 }
        failing_message.define_singleton_method(:update_column) { |_column, _value| raise StandardError, "nope" }
        tracker = ModelInteractionTracker.new(context: { account: @account, message: failing_message })

        Rails.logger.expects(:error).with(regexp_matches(/Failed to persist tool trace/))
        tracker.send(:persist_tool_trace!)
      end

      test "persist_tool_trace is no-op when message does not support update_column" do
        tracker = ModelInteractionTracker.new(context: { account: @account, message: Object.new })
        assert_nothing_raised { tracker.send(:persist_tool_trace!) }
      end

      test "compute_duration_ms returns nil before timing starts" do
        tracker = ModelInteractionTracker.new(context: @context)
        assert_nil tracker.send(:compute_duration_ms)
      end

      test "recordable supports account lookup through space" do
        tracker = ModelInteractionTracker.new(context: { message: @message, space: OpenStruct.new(account: @account) })
        assert tracker.send(:recordable?)
      end

      test "track method persists tool trace for backward compatibility" do
        tracker = ModelInteractionTracker.new(context: @context)

        # track() should persist tool trace and not raise
        # It may return a value from persist_tool_trace!, we just care it doesn't error
        assert_nothing_raised { tracker.track(nil) }
        assert_nothing_raised { tracker.track(OpenStruct.new(response: nil)) }
      end
    end
  end
end
