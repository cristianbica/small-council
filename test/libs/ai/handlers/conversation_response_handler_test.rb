# frozen_string_literal: true

require "test_helper"

module AI
  module Handlers
    class ConversationResponseHandlerTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
        @message = messages(:pending)
        @context = AI::Contexts::ConversationContext.new(
          conversation: @conversation,
          message: @message
        )
        @handler = ConversationResponseHandler.new(context: @context)
      end

      test "handle updates message content and status on success" do
        result = AI::Result.new
        result.content = "Generated response"

        @handler.handle(result)

        assert_equal "Generated response", @message.reload.content
        assert_equal "complete", @message.status
      end

      test "handle auto-retries on error up to 2 times then marks error" do
        parent = messages(:one)
        advisor = advisors(:one)

        # Create an error reply
        error_reply = @conversation.messages.create!(
          account: @account,
          sender: advisor,
          role: "advisor",
          parent_message: parent,
          content: "...",
          status: "pending",
          debug_data: {}
        )

        parent.update!(pending_advisor_ids: [ advisor.id.to_s ])

        context = AI::Contexts::ConversationContext.new(
          conversation: @conversation,
          message: error_reply
        )

        result = AI::Result.new
        result.error = StandardError.new("API Error")

        # Stub all AI calls - we just want to verify state changes
        AI.stubs(:generate_advisor_response)

        # First error - triggers retry #1
        handler = ConversationResponseHandler.new(context: context)
        handler.handle(result)
        assert_equal "pending", error_reply.reload.status
        assert_equal 1, error_reply.debug_data["retry_count"]

        # Second error - triggers retry #2
        handler = ConversationResponseHandler.new(context: context)
        handler.handle(result)
        assert_equal "pending", error_reply.reload.status
        assert_equal 2, error_reply.debug_data["retry_count"]
        assert_includes parent.reload.pending_advisor_ids, advisor.id.to_s, "Should still be pending after 2 retries"

        # Third error - max retries reached
        handler = ConversationResponseHandler.new(context: context)
        handler.handle(result)
        assert_equal "error", error_reply.reload.status
        assert_not_includes parent.reload.pending_advisor_ids, advisor.id.to_s, "Should be removed from pending after max retries"
      end

      test "handle auto-retries on empty response up to 2 times then marks error" do
        parent = messages(:one)
        advisor = advisors(:one)

        empty_reply = @conversation.messages.create!(
          account: @account,
          sender: advisor,
          role: "advisor",
          parent_message: parent,
          content: "...",
          status: "pending",
          debug_data: {}
        )

        parent.update!(pending_advisor_ids: [ advisor.id.to_s ])

        context = AI::Contexts::ConversationContext.new(
          conversation: @conversation,
          message: empty_reply
        )

        result = AI::Result.new
        result.content = ""  # Empty response

        # Stub all AI calls
        AI.stubs(:generate_advisor_response)

        # First empty - triggers retry #1
        handler = ConversationResponseHandler.new(context: context)
        handler.handle(result)
        assert_equal "pending", empty_reply.reload.status
        assert_equal 1, empty_reply.debug_data["retry_count"]

        # Second empty - triggers retry #2
        handler = ConversationResponseHandler.new(context: context)
        handler.handle(result)
        assert_equal "pending", empty_reply.reload.status
        assert_equal 2, empty_reply.debug_data["retry_count"]

        # Third empty - max retries reached
        handler = ConversationResponseHandler.new(context: context)
        handler.handle(result)
        assert_equal "error", empty_reply.reload.status
        assert_not_includes parent.reload.pending_advisor_ids, advisor.id.to_s
      end
    end
  end
end
