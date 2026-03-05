# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Conversations
      class AskAdvisorToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          @tool = AskAdvisorTool.new

          # Create council and conversation
          @council = @space.councils.create!(
            account: @account,
            name: "Test Council",
            user: @user
          )
          @conversation = @council.conversations.create!(
            account: @account,
            user: @user,
            title: "Test Conversation",
            space: @space
          )

          # Create test advisors
          @advisor1 = @space.advisors.create!(
            account: @account,
            name: "Test Advisor One",
            system_prompt: "You are a test advisor"
          )
          @advisor2 = @space.advisors.create!(
            account: @account,
            name: "Test Advisor Two",
            system_prompt: "You are another test advisor"
          )

          # Stub the job to avoid actually enqueuing
          GenerateAdvisorResponseJob.stubs(:perform_later).returns(true)
        end

        teardown do
          GenerateAdvisorResponseJob.unstub(:perform_later)
        end

        test "name returns ask_advisor" do
          assert_equal "ask_advisor", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
          assert @tool.description.include?("advisor")
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:advisor_name)
          assert params[:properties].key?(:question)
          assert_includes params[:required], :advisor_name
          assert_includes params[:required], :question
        end

        test "execute returns error without context" do
          error = assert_raises(ArgumentError) do
            @tool.execute({ advisor_name: "Test", question: "Hello" }, {})
          end
          assert_match(/Missing required context: space, conversation/, error.message)
        end

        test "execute returns error without advisor_name" do
          result = @tool.execute({ question: "Hello" }, { space: @space, conversation: @conversation })
          assert_not result[:success]
          assert_equal "advisor_name is required", result[:error]
        end

        test "execute returns error without question" do
          result = @tool.execute({ advisor_name: "Test" }, { space: @space, conversation: @conversation })
          assert_not result[:success]
          assert_equal "question is required", result[:error]
        end

        test "execute finds advisor by exact name match" do
          result = @tool.execute(
            { advisor_name: "test-advisor-one", question: "What do you think?" },
            { space: @space, conversation: @conversation, user: @user }
          )

          assert result[:success]
          assert_equal @advisor1.id, result[:advisor_id]
          assert_equal "test-advisor-one", result[:advisor_name]
        end

        test "execute finds advisor by partial name match" do
          result = @tool.execute(
            { advisor_name: "advisor-two", question: "What do you think?" },
            { space: @space, conversation: @conversation, user: @user }
          )

          assert result[:success]
          assert_equal @advisor2.id, result[:advisor_id]
        end

        test "execute returns error when advisor not found" do
          result = @tool.execute(
            { advisor_name: "Nonexistent Advisor", question: "What do you think?" },
            { space: @space, conversation: @conversation, user: @user }
          )

          assert_not result[:success]
          assert_match(/not found/, result[:error])
          assert result[:available_advisors].present?
        end

        test "execute returns error when asking self" do
          result = @tool.execute(
            { advisor_name: "test-advisor-one", question: "What do you think?" },
            { space: @space, conversation: @conversation, user: @user, advisor: @advisor1 }
          )

          assert_not result[:success]
          assert_match(/Cannot ask yourself/, result[:error])
        end

        test "execute creates mention message" do
          message_count_before = @conversation.messages.count

          result = @tool.execute(
            { advisor_name: "test-advisor-one", question: "What is your opinion?" },
            { space: @space, conversation: @conversation, user: @user }
          )

          assert result[:success]
          assert result[:message_id].present?
          assert_equal message_count_before + 1, @conversation.messages.count

          message = @conversation.messages.find(result[:message_id])
          assert message.content.include?("@test-advisor-one")
          assert message.content.include?("What is your opinion?")
          assert_equal "user", message.role
          assert_equal @user, message.sender
        end

        test "execute works with advisor as sender" do
          result = @tool.execute(
            { advisor_name: "test-advisor-two", question: "Please advise" },
            { space: @space, conversation: @conversation, advisor: @advisor1 }
          )

          assert result[:success]
          message = @conversation.messages.find(result[:message_id])
          assert_equal @advisor1, message.sender
        end
      end
    end
  end
end
