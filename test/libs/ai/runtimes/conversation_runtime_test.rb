# frozen_string_literal: true

require "test_helper"

module AI
  module Runtimes
    class ConversationRuntimeTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
        @conversation.ensure_scribe_present!
        @runtime = ConversationRuntime.new(@conversation)
      end

      test "user_posted raises NotImplementedError in base class" do
        message = messages(:one)
        assert_raises(NotImplementedError) do
          @runtime.user_posted(message)
        end
      end

      test "advisor_responded resolves advisor from pending list" do
        parent = messages(:one)
        advisor = advisors(:one)

        # Create reply first
        reply = @conversation.messages.create!(
          account: @account,
          sender: advisor,
          role: "advisor",
          parent_message: parent,
          content: "Response",
          status: "complete"
        )

        # Use string IDs to match how they're stored
        parent.update!(pending_advisor_ids: [ reply.sender_id.to_s ])

        @runtime.advisor_responded(reply)

        # Verify that the advisor was removed from pending
        assert_empty parent.reload.pending_advisor_ids
      end

      test "advisor_responded triggers next pending advisor response" do
        parent = messages(:one)
        advisor1 = advisors(:one)
        advisor2 = advisors(:two)

        # Create pending message for advisor2
        pending = @conversation.messages.create!(
          account: @account,
          sender: advisor2,
          role: "advisor",
          parent_message: parent,
          content: "...",
          status: "pending"
        )

        # Create reply from advisor1
        reply = @conversation.messages.create!(
          account: @account,
          sender: advisor1,
          role: "advisor",
          parent_message: parent,
          content: "Response",
          status: "complete"
        )

        parent.update!(pending_advisor_ids: [ reply.sender_id.to_s, pending.sender_id.to_s ])

        AI.expects(:generate_advisor_response)

        @runtime.advisor_responded(reply)
      end

      test "advisor_responded returns early if message is not a reply" do
        message = messages(:one)
        message.stubs(:reply?).returns(false)

        AI.expects(:generate_advisor_response).never

        @runtime.advisor_responded(message)
      end

      test "advisor_responded handles compaction messages" do
        parent = messages(:one)
        scribe = advisors(:'scribe-space-one')

        # Create a compaction message
        compaction_msg = @conversation.messages.create!(
          account: @account,
          sender: scribe,
          role: "advisor",
          parent_message: parent,
          content: "Compacted summary",
          status: "complete",
          message_type: "compaction",
          metadata: { compaction_for_message_id: parent.id }
        )

        # Expect the runtime to handle compaction completion
        @runtime.expects(:handle_compaction_complete).with(compaction_msg)

        @runtime.advisor_responded(compaction_msg)
      end

      test "message_resolved does not request compaction when under threshold" do
        message = messages(:one)

        # Ensure we're under threshold
        @runtime.stubs(:compaction_required?).returns(false)

        AI.expects(:compact_conversation).never

        @runtime.message_resolved(message)
      end

      test "message_resolved requests compaction when from scribe and compaction required" do
        # Create a message from scribe
        scribe = advisors(:'scribe-space-one')
        message = @conversation.messages.create!(
          account: @account,
          sender: scribe,
          role: "advisor",
          content: "Scribe summary",
          status: "complete"
        )

        @runtime.stubs(:compaction_required?).returns(true)

        AI.expects(:compact_conversation).once

        @runtime.message_resolved(message)
      end

      test "request_message_compaction creates compaction message" do
        message = messages(:one)
        scribe = advisors(:'scribe-space-one')

        AI.stubs(:compact_conversation)

        @runtime.send(:request_message_compaction, message)

        compaction = @conversation.messages.compaction.last
        assert compaction
        assert_equal scribe, compaction.sender
        assert_equal "pending", compaction.status
        assert_equal message.id, compaction.metadata["compaction_for_message_id"]
      end

      test "handle_compaction_complete resolves original message" do
        parent = messages(:one)
        scribe = advisors(:'scribe-space-one')

        # Create pending advisor to prevent full resolution
        pending_advisor = advisors(:two)
        parent.update!(pending_advisor_ids: [ pending_advisor.id.to_s ])

        # Create compaction message
        compaction_msg = @conversation.messages.create!(
          account: @account,
          sender: scribe,
          role: "advisor",
          content: "Compacted summary",
          status: "complete",
          message_type: "compaction",
          metadata: { compaction_for_message_id: parent.id }
        )

        # Mock the next steps
        @runtime.expects(:message_resolved).with(parent)

        @runtime.send(:handle_compaction_complete, compaction_msg)
      end

      test "compaction_required? returns true when content exceeds threshold" do
        # Create messages totaling more than 25k chars
        10.times do |i|
          @conversation.messages.create!(
            account: @account,
            sender: @conversation.user,
            role: "user",
            content: "x" * 3000,
            status: "complete"
          )
        end

        assert @runtime.send(:compaction_required?)
      end

      test "compaction_required? returns false when under threshold" do
        # Create a few small messages
        3.times do |i|
          @conversation.messages.create!(
            account: @account,
            sender: @conversation.user,
            role: "user",
            content: "Short message",
            status: "complete"
          )
        end

        assert_not @runtime.send(:compaction_required?)
      end

      test "since_last_compaction considered in compaction_required?" do
        # Create first compaction
        scribe = advisors(:'scribe-space-one')
        @conversation.messages.create!(
          account: @account,
          sender: scribe,
          role: "advisor",
          content: "First compaction",
          status: "complete",
          message_type: "compaction"
        )

        # Create messages after compaction - total less than threshold
        3.times do |i|
          @conversation.messages.create!(
            account: @account,
            sender: @conversation.user,
            role: "user",
            content: "x" * 1000,
            status: "complete"
          )
        end

        # Should not require compaction since we're under threshold since last compaction
        assert_not @runtime.send(:compaction_required?)
      end
    end
  end
end
