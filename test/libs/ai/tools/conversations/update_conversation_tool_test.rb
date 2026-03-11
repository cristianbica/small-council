# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Conversations
      class UpdateConversationToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @conversation = conversations(:one)
          @context = AI::Contexts::ConversationContext.new(conversation: @conversation)
          @tool = UpdateConversationTool.new(@context)
        end

        test "updates title for current conversation and marks agent_generated" do
          result = @tool.execute(conversation_id: @conversation.id, title: "  New   Focused Title  ")

          assert_equal true, result[:success]
          assert_equal "New Focused Title", @conversation.reload.title
          assert_equal "agent_generated", @conversation.title_state
        end

        test "rejects mismatched conversation id" do
          result = @tool.execute(conversation_id: @conversation.id + 999, title: "Nope")

          assert_equal false, result[:success]
          assert_match(/Conversation mismatch/, result[:error])
        end

        test "rejects blank title" do
          result = @tool.execute(conversation_id: @conversation.id, title: "   ")

          assert_equal false, result[:success]
          assert_match(/title is required/, result[:error])
        end
      end
    end
  end
end
