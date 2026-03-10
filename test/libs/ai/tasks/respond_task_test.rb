# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  module Tasks
    class RespondTaskTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
        @advisor = advisors(:one)
        @context = AI::Contexts::ConversationContext.new(
          conversation: @conversation,
          advisor: @advisor
        )
      end

      test "system_prompt includes base advisor content" do
        task = RespondTask.new(context: @context)

        result = task.send(:system_prompt)

        assert_includes result, "You are an advisor participating"
      end

      test "system_prompt appends custom prompt when provided" do
        custom_prompt_content = "Custom RoE instructions for this session"
        # Stub all AI.prompt calls - both for base agent prompt and custom prompt
        AI.stubs(:prompt).returns("Base prompt")
        AI.stubs(:prompt).with(:consensus_moderator, context: @context).returns(custom_prompt_content)

        task = RespondTask.new(context: @context, prompt: :consensus_moderator)
        result = task.send(:system_prompt)

        assert_includes result, custom_prompt_content
      end

      test "thinking_placeholder? returns true for pending messages with ..." do
        task = RespondTask.new(context: @context)

        message = messages(:pending)

        assert task.send(:thinking_placeholder?, message)
      end

      test "thinking_placeholder? returns false for complete messages" do
        task = RespondTask.new(context: @context)

        message = messages(:one)

        refute task.send(:thinking_placeholder?, message)
      end

      test "build_tool_trace_messages includes only tool_result entries" do
        message = messages(:two)
        message.update!(tool_calls: [
          { "type" => "tool_call", "id" => "call-1", "name" => "memories-list", "arguments" => {} },
          { "type" => "tool_result", "tool_call_id" => "call-1", "result" => { "ok" => true } }
        ])

        task = RespondTask.new(context: @context)
        result = task.send(:build_tool_trace_messages, message)

        assert_equal 1, result.size
        assert_equal :tool, result.first[:role]
        assert_equal "call-1", result.first[:tool_call_id]
        assert_equal({ "ok" => true }.to_json, result.first[:content])
      end

      test "mark_message_responding! updates pending message status" do
        pending_message = messages(:pending)
        context = AI::Contexts::ConversationContext.new(
          conversation: @conversation,
          advisor: @advisor,
          message: pending_message
        )
        task = RespondTask.new(context: context)

        task.send(:mark_message_responding!)

        assert_equal "responding", pending_message.reload.status
      end

      test "mark_message_responding! does nothing for non-pending message" do
        complete_message = messages(:one)
        context = AI::Contexts::ConversationContext.new(
          conversation: @conversation,
          advisor: @advisor,
          message: complete_message
        )
        task = RespondTask.new(context: context)

        assert_no_changes -> { complete_message.reload.status } do
          task.send(:mark_message_responding!)
        end
      end

      test "normalized_role maps advisor to assistant and others to symbol" do
        task = RespondTask.new(context: @context)

        assert_equal :assistant, task.send(:normalized_role, :advisor)
        assert_equal :user, task.send(:normalized_role, "user")
      end

      test "sender_display_name supports display_name, name and fallback to_s" do
        task = RespondTask.new(context: @context)

        assert_equal "Disp", task.send(:sender_display_name, OpenStruct.new(display_name: "Disp"))
        assert_equal "Name", task.send(:sender_display_name, OpenStruct.new(name: "Name"))
        assert_equal "123", task.send(:sender_display_name, 123)
      end

      test "conversation_messages excludes advisor replies to current message" do
        current_message = messages(:one)
        context = AI::Contexts::ConversationContext.new(
          conversation: @conversation,
          advisor: @advisor,
          message: current_message
        )
        task = RespondTask.new(context: context)

        messages = task.send(:conversation_messages)

        refute messages.any? { |m| m[:content].to_s.include?("I have some thoughts") }
      end

      test "build_tool_trace_messages returns empty for invalid entry types" do
        message = messages(:two)
        message.update!(tool_calls: [ "bad", { "type" => "tool_call", "id" => "c1" } ])
        task = RespondTask.new(context: @context)

        assert_equal [], task.send(:build_tool_trace_messages, message)
      end

      test "outbound_message_content prefixes speaker label" do
        task = RespondTask.new(context: @context)

        assert_equal "[speaker: Alice] hi", task.send(:outbound_message_content, "hi", "Alice", :user)
        assert_equal "[speaker: user] hi", task.send(:outbound_message_content, "hi", nil, :user)
      end

      test "prepare sends instructions and omits sender_name from outbound payload" do
        chat = mock("chat")
        task = RespondTask.new(context: @context)
        task.stubs(:system_prompt).returns("System text")
        task.stubs(:conversation_messages).returns([
          { role: :user, content: "Hello", sender_name: "Alice" }
        ])

        chat.expects(:instructions).with("System text")
        chat.expects(:add_message).with(role: :user, content: "Hello")

        task.prepare(chat)
      end

      test "run marks pending message then delegates to base run" do
        pending_message = messages(:pending)
        context = AI::Contexts::ConversationContext.new(
          conversation: @conversation,
          advisor: @advisor,
          message: pending_message
        )
        task = RespondTask.new(context: context)

        chat = mock("chat")
        result = AI::Result.new

        AI::Client.expects(:chat).returns(chat)
        chat.expects(:tools).never
        chat.expects(:instructions)
        chat.expects(:add_message).at_least_once
        chat.expects(:complete).with(result) do |r|
          r.response = OpenStruct.new(content: "done")
        end

        task.run(result)

        assert_equal "responding", pending_message.reload.status
        assert_equal "done", result.content
      end

      test "build_tool_trace_messages returns empty when message has no tool_calls method" do
        task = RespondTask.new(context: @context)
        message = OpenStruct.new

        assert_equal [], task.send(:build_tool_trace_messages, message)
      end

      test "build_tool_trace_messages rescues unexpected errors" do
        task = RespondTask.new(context: @context)
        message = Object.new
        message.define_singleton_method(:tool_calls) { raise "boom" }

        assert_equal [], task.send(:build_tool_trace_messages, message)
      end
    end
  end
end
