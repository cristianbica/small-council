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

      test "handle writes error state on failure" do
        result = AI::Result.new
        result.error = StandardError.new("Generation failed")

        @handler.handle(result)

        assert_equal "Error: Generation failed", @message.reload.content
        assert_equal "error", @message.status
      end
    end
  end
end
