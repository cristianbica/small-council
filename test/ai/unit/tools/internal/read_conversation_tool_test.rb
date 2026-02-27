# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class ReadConversationToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = @account.users.first || @account.users.create!(email: "test@example.com", password: "password123")
          @council = @space.councils.first || @space.councils.create!(name: "Test Council", account: @account, user: @user)
          @tool = ReadConversationTool.new

          @conversation = @council.conversations.create!(
            account: @account,
            user: @user,
            title: "Test Conversation"
          )

          # Create messages
          5.times do |i|
            @conversation.messages.create!(
              account: @account,
              sender: @user,
              role: "user",
              content: "Message #{i + 1} content here"
            )
          end
        end

        test "name returns read_conversation" do
          assert_equal "read_conversation", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
          assert @tool.description.include?("messages")
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:conversation_id)
          assert params[:properties].key?(:limit)
          assert params[:properties].key?(:offset)
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

        test "execute returns conversation messages" do
          result = @tool.execute({ conversation_id: @conversation.id }, { space: @space })

          assert result[:success]
          assert_equal @conversation.id, result[:conversation_id]
          assert_equal "Test Conversation", result[:conversation_title]
          assert_equal @council.name, result[:council]
          assert_equal 5, result[:total_count]
          assert_equal 5, result[:count]
        end

        test "execute returns error for nonexistent conversation" do
          result = @tool.execute({ conversation_id: 999999 }, { space: @space })

          assert_not result[:success]
          assert_match(/not found/, result[:error])
        end

        test "execute only finds conversations in context space" do
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

        test "execute respects limit parameter" do
          result = @tool.execute(
            { conversation_id: @conversation.id, limit: 2 },
            { space: @space }
          )

          assert result[:success]
          assert_equal 2, result[:count]
          assert_equal 2, result[:limit]
        end

        test "execute enforces max limit" do
          result = @tool.execute(
            { conversation_id: @conversation.id, limit: 200 },
            { space: @space }
          )

          assert result[:success]
          assert result[:limit] <= 100
        end

        test "execute enforces min limit" do
          result = @tool.execute(
            { conversation_id: @conversation.id, limit: 0 },
            { space: @space }
          )

          assert result[:success]
          assert_equal 50, result[:limit]
        end

        test "execute respects offset for pagination" do
          result = @tool.execute(
            { conversation_id: @conversation.id, limit: 2, offset: 2 },
            { space: @space }
          )

          assert result[:success]
          assert_equal 2, result[:count]
          assert_equal 2, result[:offset]
        end

        test "execute returns has_more when more results available" do
          result = @tool.execute(
            { conversation_id: @conversation.id, limit: 2 },
            { space: @space }
          )

          assert result[:success]
          assert result[:has_more]
        end

        test "execute returns has_more false when no more results" do
          result = @tool.execute(
            { conversation_id: @conversation.id, limit: 10 },
            { space: @space }
          )

          assert result[:success]
          assert_not result[:has_more]
        end

        test "execute formats message data correctly" do
          result = @tool.execute({ conversation_id: @conversation.id }, { space: @space })

          message = result[:messages].first
          assert message[:id].present?
          assert message[:sender].present?
          assert message[:role].present?
          assert message[:content].present?
          assert message[:status].present?
          assert message[:created_at].present?
        end

        test "execute orders messages chronologically" do
          result = @tool.execute({ conversation_id: @conversation.id }, { space: @space })

          contents = result[:messages].map { |m| m[:content] }
          assert contents.first.include?("Message 1")
          assert contents.last.include?("Message 5")
        end
      end
    end
  end
end
