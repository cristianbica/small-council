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

    # Create a conversation
    @conversation = @account.conversations.create!(
      title: "Test RoE Flow",
      council: @council,
      user: @user,
      rules_of_engagement: :round_robin
    )
  end

  test "user can change RoE mode from conversation page" do
    get conversation_path(@conversation)
    assert_response :success

    patch conversation_path(@conversation), params: {
      conversation: { rules_of_engagement: :silent }
    }

    assert_redirected_to conversation_path(@conversation)
    follow_redirect!
    assert_response :success
  end

  test "posting message in round_robin creates placeholder" do
    assert_difference "Message.count", 2 do # user message + placeholder
      post conversation_messages_path(@conversation), params: {
        message: { content: "Hello advisors" }
      }
    end

    assert_redirected_to conversation_path(@conversation)

    placeholder = Message.last
    assert_equal @advisor, placeholder.sender
    assert_equal "system", placeholder.role
    assert_equal "pending", placeholder.status
    assert_match(/thinking/, placeholder.content)
  end

  test "posting with @mention in on_demand mode" do
    @conversation.update!(rules_of_engagement: :on_demand)

    assert_difference "Message.count", 2 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "@Helper_Bot I need help" }
      }
    end

    placeholder = Message.last
    assert_equal @advisor, placeholder.sender
  end

  test "silent mode does not create placeholders" do
    @conversation.update!(rules_of_engagement: :silent)

    assert_difference "Message.count", 1 do # only user message
      post conversation_messages_path(@conversation), params: {
        message: { content: "Hello? Anyone there?" }
      }
    end
  end

  test "consensus mode creates placeholder for all advisors" do
    advisor2 = @account.advisors.create!(
      name: "Second Advisor",
      system_prompt: "You are advisor 2",
      llm_model: @llm_model,
      space: @space
    )
    @council.advisors << advisor2
    @conversation.update!(rules_of_engagement: :consensus)

    assert_difference "Message.count", 3 do # user + 2 advisors
      post conversation_messages_path(@conversation), params: {
        message: { content: "Group discussion" }
      }
    end

    placeholders = Message.last(2)
    assert_equal 2, placeholders.count { |m| m.pending? }
  end

  test "changing RoE mid-conversation affects next message" do
    # First message with round_robin
    post conversation_messages_path(@conversation), params: {
      message: { content: "First message" }
    }

    @conversation.update!(rules_of_engagement: :silent)

    # Second message should not trigger advisor
    assert_difference "Message.count", 1 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Second message" }
      }
    end
  end
end
