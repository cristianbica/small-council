# frozen_string_literal: true

require "test_helper"

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
    end
  end
end
