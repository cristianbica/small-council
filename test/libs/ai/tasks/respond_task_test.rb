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
        @user = users(:one)
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

      test "conversation_messages handles compaction as previous message" do
        # Create a compaction message
        compaction = @account.messages.create!(
          conversation: @conversation,
          sender: @advisor,
          role: "advisor",
          content: "Compaction summary",
          message_type: "compaction",
          status: "complete"
        )

        # Create the current message responding to the compaction
        current_message = @account.messages.create!(
          conversation: @conversation,
          sender: @user,
          role: "user",
          content: "What should we do next?"
        )

        context = AI::Contexts::ConversationContext.new(
          conversation: @conversation,
          advisor: @advisor,
          message: current_message
        )
        task = RespondTask.new(context: context)

        # Should not raise an error
        messages = task.send(:conversation_messages)
        assert_kind_of Array, messages
      end

      test "conversation_messages excludes current message when previous is compaction" do
        # Create pre-compaction message
        pre_msg = @account.messages.create!(
          conversation: @conversation,
          sender: @user,
          role: "user",
          content: "Before compaction"
        )

        # Create compaction message
        compaction = @account.messages.create!(
          conversation: @conversation,
          sender: @advisor,
          role: "advisor",
          content: "Compaction summary",
          message_type: "compaction",
          status: "complete"
        )

        # Create current message
        current_message = @account.messages.create!(
          conversation: @conversation,
          sender: @user,
          role: "user",
          content: "After compaction"
        )

        context = AI::Contexts::ConversationContext.new(
          conversation: @conversation,
          advisor: @advisor,
          message: current_message
        )
        task = RespondTask.new(context: context)

        messages = task.send(:conversation_messages)

        # The current message should be excluded from context
        current_content = "[speaker: User] After compaction"
        assert_not messages.any? { |m| m[:content] == current_content }
      end

      test "scribe responding after second compaction sees correct context" do
        scribe = @conversation.space.scribe_advisor
        advisor1 = advisors(:one)
        advisor2 = advisors(:two)
        # Simulate the user's flow:
        # 1. User message
        user_msg1 = @account.messages.create!(
          conversation: @conversation,
          sender: @user,
          role: "user",
          content: "Help me with a decision"
        )

        # 2. Scribe message (round 1)
        scribe_round1 = @account.messages.create!(
          conversation: @conversation,
          sender: scribe,
          role: "advisor",
          parent_message: user_msg1,
          content: "Let me gather information. @advisor1 @advisor2 please share your thoughts"
        )

        # 3. First compaction
        compaction1 = @account.messages.create!(
          conversation: @conversation,
          sender: scribe,
          role: "advisor",
          content: "Summary of initial discussion",
          message_type: "compaction",
          status: "complete"
        )

        # 4. User message (follow-up)
        user_msg2 = @account.messages.create!(
          conversation: @conversation,
          sender: @user,
          role: "user",
          content: "What are the trade-offs?"
        )

        # 5. Scribe message requesting advisors (round 2)
        scribe_request = @account.messages.create!(
          conversation: @conversation,
          sender: scribe,
          role: "advisor",
          parent_message: user_msg2,
          content: "@advisor1 @advisor2 please analyze the trade-offs"
        )

        # 6. Advisor 1 responds
        advisor1_response = @account.messages.create!(
          conversation: @conversation,
          sender: advisor1,
          role: "advisor",
          parent_message: scribe_request,
          content: "Here are the cost trade-offs..."
        )

        # 7. Advisor 2 responds
        advisor2_response = @account.messages.create!(
          conversation: @conversation,
          sender: advisor2,
          role: "advisor",
          parent_message: scribe_request,
          content: "Here are the timeline trade-offs..."
        )

        # 8. Second compaction (after round 2)
        compaction2 = @account.messages.create!(
          conversation: @conversation,
          sender: scribe,
          role: "advisor",
          content: "Summary of trade-off analysis from advisors",
          message_type: "compaction",
          status: "complete"
        )

        # 9. Scribe responds to scribe_request being resolved (round 3)
        # This is the critical test - the scribe is moderating round 3
        scribe_round3 = @account.messages.create!(
          conversation: @conversation,
          sender: @advisor,
          role: "advisor",
          content: "..."
        )

        # Create context for the scribe responding in round 3
        context = AI::Contexts::ConversationContext.new(
          conversation: @conversation,
          advisor: scribe,
          message: scribe_round3
        )
        task = RespondTask.new(context: context)

        messages = task.send(:conversation_messages)
        message_contents = messages.map { |m| m[:content] }

        # Should include messages from after first compaction
        assert message_contents.any? { |c| c.include?("What are the trade-offs?") },
          "Should include user message after first compaction"
        assert message_contents.any? { |c| c.include?("analyze the trade-offs") },
          "Should include scribe request"
        assert message_contents.any? { |c| c.include?("cost trade-offs") },
          "Should include advisor 1 response"
        assert message_contents.any? { |c| c.include?("timeline trade-offs") },
          "Should include advisor 2 response"

        # Should NOT include the compaction that just happened (compaction2)
        assert_not message_contents.any? { |c| c.include?("Summary of trade-off analysis") },
          "Should NOT include the second compaction message itself"
      end

      test "conversation_messages excludes info messages and includes memory_attachment messages" do
        info_message = @account.messages.create!(
          conversation: @conversation,
          sender: @user,
          role: "system",
          content: "user added fixture-counselor-two",
          message_type: "info",
          status: "complete"
        )

        attachment_message = @account.messages.create!(
          conversation: @conversation,
          sender: @user,
          role: "user",
          content: "Attached memory #1: Test Knowledge Memory",
          message_type: "memory_attachment",
          status: "complete"
        )

        task = RespondTask.new(context: @context)
        messages = task.send(:conversation_messages)
        contents = messages.map { |entry| entry[:content] }

        assert contents.any? { |entry| entry.include?(attachment_message.content) }
        assert_not contents.any? { |entry| entry.include?(info_message.content) }
      end
    end
  end
end
