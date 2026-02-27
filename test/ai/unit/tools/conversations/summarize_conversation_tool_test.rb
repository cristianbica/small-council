# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Conversations
      class SummarizeConversationToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = @account.users.first || @account.users.create!(email: "test@example.com", password: "password123")
          @council = @space.councils.first || @space.councils.create!(name: "Test Council", account: @account, user: @user)
          @conversation = @council.conversations.create!(
            account: @account,
            user: @user,
            title: "Project Discussion"
          )
          @tool = SummarizeConversationTool.new

          # Create messages
          @advisor = @space.advisors.create!(
            account: @account,
            name: "Test Advisor",
            system_prompt: "You are a test advisor"
          )

          @conversation.messages.create!(
            account: @account,
            sender: @user,
            role: "user",
            content: "Can we discuss the project timeline?",
            status: "complete"
          )
          @conversation.messages.create!(
            account: @account,
            sender: @advisor,
            role: "advisor",
            content: "Sure, I think we need 3 months for completion.",
            status: "complete"
          )
        end

        test "name returns summarize_conversation" do
          assert_equal "summarize_conversation", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
          assert @tool.description.include?("summary")
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:style)
          assert params[:properties].key?(:message_limit)
          assert_includes params[:required], :style
          assert_includes params[:properties][:style][:enum], "brief"
          assert_includes params[:properties][:style][:enum], "detailed"
          assert_includes params[:properties][:style][:enum], "bullet_points"
        end

        test "execute returns error without context" do
          error = assert_raises(ArgumentError) do
            @tool.execute({ style: "brief" }, {})
          end
          assert_match(/Missing required context: conversation/, error.message)
        end

        test "execute returns summary with brief style" do
          result = @tool.execute(
            { style: "brief" },
            { conversation: @conversation }
          )

          assert result[:success]
          assert result[:summary].present?
          assert result[:summary].include?("Project Discussion")
          assert result[:message_count] >= 2
          assert_equal "brief", result[:style]
          assert_equal @conversation.id, result[:conversation_id]
        end

        test "execute returns summary with detailed style" do
          result = @tool.execute(
            { style: "detailed" },
            { conversation: @conversation }
          )

          assert result[:success]
          assert result[:summary].present?
          assert result[:summary].include?("Project Discussion")
          assert_equal "detailed", result[:style]
        end

        test "execute returns summary with bullet_points style" do
          result = @tool.execute(
            { style: "bullet_points" },
            { conversation: @conversation }
          )

          assert result[:success]
          assert result[:summary].present?
          assert result[:summary].include?("•") || result[:summary].include?("Project Discussion")
          assert_equal "bullet_points", result[:style]
        end

        test "execute handles empty conversation" do
          empty_conversation = @council.conversations.create!(
            account: @account,
            user: @user,
            title: "Empty Discussion"
          )

          result = @tool.execute(
            { style: "brief" },
            { conversation: empty_conversation }
          )

          assert result[:success]
          assert result[:summary].include?("No messages")
          assert_equal 0, result[:message_count]
        end

        test "execute respects message_limit" do
          # Create many messages
          10.times do |i|
            @conversation.messages.create!(
              account: @account,
              sender: @user,
              role: "user",
              content: "Message #{i}",
              status: "complete"
            )
          end

          result = @tool.execute(
            { style: "brief", message_limit: 5 },
            { conversation: @conversation }
          )

          assert result[:success]
          assert result[:message_count] <= 5
        end

        test "execute enforces max message_limit" do
          result = @tool.execute(
            { style: "brief", message_limit: 200 },
            { conversation: @conversation }
          )

          assert result[:success]
          # Should be capped at 100
          assert result[:message_count] <= 100
        end
      end
    end
  end
end
