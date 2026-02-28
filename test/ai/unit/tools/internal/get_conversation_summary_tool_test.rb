# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class GetConversationSummaryToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = @account.users.first || @account.users.create!(email: "test@example.com", password: "password123")
          @council = @space.councils.first || @space.councils.create!(name: "Test Council", account: @account, user: @user)
          @advisor = @space.advisors.create!(
            account: @account,
            name: "Test Advisor",
            system_prompt: "You are a test advisor"
          )
          @tool = GetConversationSummaryTool.new

          @conversation = @council.conversations.create!(
            account: @account,
            user: @user,
            title: "Test Conversation",
            status: "resolved"
          )

          # Add advisor as participant
          @conversation.conversation_participants.create!(
            advisor: @advisor,
            role: :advisor,
            position: 0
          )
        end

        test "name returns get_conversation_summary" do
          assert_equal "get_conversation_summary", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
          assert @tool.description.include?("summary")
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:conversation_id)
          assert_includes params[:required], :conversation_id
        end

        test "execute returns error without context" do
          error = assert_raises(ArgumentError) do
            @tool.execute({ conversation_id: @conversation.id }, {})
          end
          assert_match(/Missing required context: space/, error.message)
        end

        test "execute returns error without conversation_id" do
          result = @tool.execute({}, { space: @space })
          assert_not result[:success]
          assert_equal "conversation_id is required", result[:error]
        end

        test "execute returns error for nonexistent conversation" do
          result = @tool.execute({ conversation_id: 999999 }, { space: @space })

          assert_not result[:success]
          assert_match(/not found/, result[:error])
        end

        test "execute returns found summary from memory" do
          # Create a conversation_summary memory
          summary_memory = @space.memories.create!(
            account: @account,
            source: @conversation,
            title: "Summary: Test Conversation",
            content: "This conversation was about testing the summary tool.",
            memory_type: "conversation_summary",
            status: "active",
            created_by: @advisor
          )

          result = @tool.execute({ conversation_id: @conversation.id }, { space: @space })

          assert result[:success]
          assert result[:found]
          assert_equal @conversation.id, result[:conversation_id]
          assert_equal "Test Conversation", result[:conversation_title]
          assert_equal "This conversation was about testing the summary tool.", result[:summary]
          assert_equal summary_memory.id, result[:memory_id]
        end

        test "execute returns summary from conversation memory field" do
          @conversation.update!(
            memory: { summary: "This is the conversation's internal summary." }.to_json
          )

          result = @tool.execute({ conversation_id: @conversation.id }, { space: @space })

          assert result[:success]
          assert result[:found]
          assert_equal "This is the conversation's internal summary.", result[:summary]
          assert_equal "conversation.memory", result[:source]
        end

        test "execute prefers memory over conversation field" do
          # Create both
          @conversation.update!(
            memory: { summary: "Internal summary." }.to_json
          )
          @space.memories.create!(
            account: @account,
            source: @conversation,
            title: "Summary",
            content: "Memory summary.",
            memory_type: "conversation_summary",
            status: "active"
          )

          result = @tool.execute({ conversation_id: @conversation.id }, { space: @space })

          assert result[:success]
          assert result[:found]
          # Memory is queried first and returns if found
          assert result[:memory_id].present?
        end

        test "execute returns not found when no summary exists" do
          result = @tool.execute({ conversation_id: @conversation.id }, { space: @space })

          assert result[:success]
          assert_not result[:found]
          assert_equal @conversation.id, result[:conversation_id]
          assert result[:message].include?("No stored summary")
          assert_equal "resolved", result[:status]
        end

        test "execute only searches in context space" do
          other_space = @account.spaces.create!(name: "Other Space")
          other_council = other_space.councils.create!(name: "Other Council", account: @account, user: @user)
          other_conv = other_council.conversations.create!(
            account: @account,
            user: @user,
            title: "Other Conversation"
          )

          result = @tool.execute({ conversation_id: other_conv.id }, { space: @space })

          assert_not result[:success]
          assert_match(/not found/, result[:error])
        end

        test "execute ignores non-conversation-summary memories" do
          @space.memories.create!(
            account: @account,
            source: @conversation,
            title: "Some Knowledge",
            content: "This is knowledge, not a summary.",
            memory_type: "knowledge",
            status: "active"
          )

          result = @tool.execute({ conversation_id: @conversation.id }, { space: @space })

          assert result[:success]
          assert_not result[:found]
        end

        test "execute ignores archived conversation_summary memories" do
          @space.memories.create!(
            account: @account,
            source: @conversation,
            title: "Archived Summary",
            content: "This is archived.",
            memory_type: "conversation_summary",
            status: "archived"
          )

          result = @tool.execute({ conversation_id: @conversation.id }, { space: @space })

          assert result[:success]
          assert_not result[:found]
        end
      end
    end
  end
end
