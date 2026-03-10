# frozen_string_literal: true

require "test_helper"

module AI
  module Runtimes
    class ConversationRuntimeTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
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
    end
  end
end
