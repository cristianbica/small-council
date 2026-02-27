# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Conversations
      class FinishConversationToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = @account.users.first || @account.users.create!(email: "test@example.com", password: "password123")
          @council = @space.councils.first || @space.councils.create!(name: "Test Council", account: @account, user: @user)
          @conversation = @council.conversations.create!(
            account: @account,
            user: @user,
            title: "Test Conversation",
            status: "active"
          )
          @advisor = @space.advisors.create!(
            account: @account,
            name: "Test Advisor",
            system_prompt: "You are a test advisor"
          )
          @tool = FinishConversationTool.new
        end

        test "name returns finish_conversation" do
          assert_equal "finish_conversation", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
          assert @tool.description.include?("finished")
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:reason)
          assert_includes params[:required], :reason
        end

        test "execute returns error without context" do
          error = assert_raises(ArgumentError) do
            @tool.execute({ reason: "Done" }, {})
          end
          assert_match(/Missing required context: conversation/, error.message)
        end

        test "execute returns error without reason" do
          result = @tool.execute({}, { conversation: @conversation })
          assert_not result[:success]
          assert_equal "reason is required", result[:error]
        end

        test "execute marks active conversation as concluding" do
          assert @conversation.active?

          # Mock ConversationLifecycle to avoid job enqueuing
          mock_lifecycle = mock()
          mock_lifecycle.expects(:begin_conclusion_process).once
          ConversationLifecycle.expects(:new).with(@conversation).returns(mock_lifecycle)

          result = @tool.execute(
            { reason: "Decision reached" },
            { conversation: @conversation, advisor: @advisor }
          )

          assert result[:success]
          assert_equal "Decision reached", result[:reason]
          assert_equal "concluding", result[:status]
          assert_equal @conversation.id, result[:conversation_id]
        end

        test "execute stores conclusion metadata" do
          mock_lifecycle = mock()
          mock_lifecycle.expects(:begin_conclusion_process).once
          ConversationLifecycle.expects(:new).returns(mock_lifecycle)

          @tool.execute(
            { reason: "All questions answered" },
            { conversation: @conversation, advisor: @advisor }
          )

          # Reload to get updated context
          @conversation.reload
          assert_equal "All questions answered", @conversation.context["conclusion_reason"]
          assert_equal "Test Advisor", @conversation.context["concluded_by"]
        end

        test "execute returns error for already concluding conversation" do
          @conversation.update!(status: :concluding)

          result = @tool.execute(
            { reason: "Done" },
            { conversation: @conversation }
          )

          assert_not result[:success]
          assert_match(/already concluding/, result[:error])
        end

        test "execute returns error for resolved conversation" do
          @conversation.update!(status: :resolved)

          result = @tool.execute(
            { reason: "Done" },
            { conversation: @conversation }
          )

          assert_not result[:success]
          assert_match(/already resolved/, result[:error])
        end

        test "execute returns error for archived conversation" do
          @conversation.update!(status: :archived)

          result = @tool.execute(
            { reason: "Done" },
            { conversation: @conversation }
          )

          assert_not result[:success]
          assert_match(/already archived/, result[:error])
        end

        test "execute stores user email when concluded by user" do
          mock_lifecycle = mock()
          mock_lifecycle.expects(:begin_conclusion_process).once
          ConversationLifecycle.expects(:new).returns(mock_lifecycle)

          @tool.execute(
            { reason: "I'm done" },
            { conversation: @conversation, user: @user }
          )

          @conversation.reload
          assert_equal @user.email, @conversation.context["concluded_by"]
        end
      end
    end
  end
end
