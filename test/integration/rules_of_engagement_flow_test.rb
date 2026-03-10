require "test_helper"

class RulesOfEngagementFlowTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:one)
    @user = users(:one)
    set_tenant(@account)
    sign_in_as(@user)

    # Create provider and model for advisors
    @provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )
    @llm_model = @provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )

    # Create a space and council with an advisor
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    @advisor = @account.advisors.create!(
      name: "Helper Bot",
      system_prompt: "You are a helper bot",
      llm_model: @llm_model,
      space: @space
    )
    @council.advisors << @advisor

    # Create a conversation with advisors as participants
    @conversation = @account.conversations.create!(
      title: "Test RoE Flow",
      council: @council,
      user: @user,
      rules_of_engagement: :open,
      space: @space
    )

    # Add advisors as participants
    @conversation.conversation_participants.create!(
      advisor: @advisor,
      role: :advisor,
      position: 0
    )
  end

  test "user can change RoE mode from conversation page" do
    get conversation_path(@conversation)
    assert_response :success

    patch conversation_path(@conversation), params: {
      conversation: { roe_type: :consensus }
    }

    assert_redirected_to conversation_path(@conversation)
    follow_redirect!
    assert_response :success
  end

  test "posting mentioned message in consensus creates placeholder for that advisor" do
    @conversation.update!(roe_type: :consensus)

    assert_difference "Message.count", 2 do # user message + placeholder
      post conversation_messages_path(@conversation), params: {
        message: { content: "Hello @helper-bot" }
      }
    end

    assert_redirected_to conversation_path(@conversation)

    placeholder = Message.last
    assert_equal @advisor, placeholder.sender
    assert_equal "advisor", placeholder.role
    assert_equal "pending", placeholder.status
    assert_equal "...", placeholder.content
  end

  test "posting with @mention in open mode" do
    @conversation.update!(roe_type: :open)

    assert_difference "Message.count", 2 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "@helper-bot I need help" }
      }
    end

    placeholder = Message.last
    assert_equal @advisor, placeholder.sender
  end

  test "open mode with single advisor creates placeholder without explicit mention" do
    @conversation.update!(roe_type: :open)

    assert_difference "Message.count", 2 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Hello? Anyone there?" }
      }
    end
  end

  test "consensus mode without mentions only stores user message" do
    advisor2 = @account.advisors.create!(
      name: "Second Advisor",
      system_prompt: "You are advisor 2",
      llm_model: @llm_model,
      space: @space
    )
    @council.advisors << advisor2
    @conversation.conversation_participants.create!(
      advisor: advisor2,
      role: :advisor,
      position: 1
    )
    @conversation.update!(roe_type: :consensus)

    assert_difference "Message.count", 1 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Group discussion" }
      }
    end
  end

  test "changing RoE mid-conversation affects next message" do
    # First message with consensus (creates placeholder)
    @conversation.update!(roe_type: :consensus)
    post conversation_messages_path(@conversation), params: {
      message: { content: "First message" }
    }

    @conversation.update!(roe_type: :open)

    # Open mode with one advisor still schedules that advisor.
    assert_difference "Message.count", 2 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Second message" }
      }
    end
  end
end
