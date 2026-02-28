require "test_helper"

class ConversationFlowTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
  end

  test "full conversation flow" do
    # Sign in as user
    sign_in_as(@user)
    set_tenant(@account)

    # Create a space and advisor
    space = @account.spaces.first || @account.spaces.create!(name: "General")
    provider = @account.providers.create!(name: "Test Provider", provider_type: "openai", api_key: "test-key")
    llm_model = provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      space: space,
      llm_model: llm_model
    )

    # Create a council with advisor
    post councils_url, params: { council: { name: "Test Council", description: "For testing" } }
    council = Council.last
    council.advisors << advisor
    assert_redirected_to council_url(council)

    # Start a conversation
    get new_council_conversation_url(council)
    assert_response :success

    post council_conversations_url(council), params: {
      conversation: { title: "First conversation topic" }
    }
    conversation = Conversation.last
    assert_redirected_to conversation_url(conversation)

    # Verify conversation and first message were created
    assert_equal "First conversation topic", conversation.title
    assert_equal @user, conversation.user
    assert_equal 1, conversation.messages.count
    assert_equal "First conversation topic", conversation.messages.first.content

    # Post additional messages
    post conversation_messages_url(conversation), params: {
      message: { content: "Second message" }
    }
    assert_redirected_to conversation_url(conversation)

    post conversation_messages_url(conversation), params: {
      message: { content: "Third message" }
    }
    assert_redirected_to conversation_url(conversation)

    # Verify all messages appear in correct order
    get conversation_url(conversation)
    assert_response :success

    messages = conversation.messages.chronological.to_a
    assert_equal 3, messages.count
    assert_equal "First conversation topic", messages[0].content
    assert_equal "Second message", messages[1].content
    assert_equal "Third message", messages[2].content

    # Verify messages appear on the page
    assert_select ".whitespace-pre-wrap", "First conversation topic"
    assert_select ".whitespace-pre-wrap", "Second message"
    assert_select ".whitespace-pre-wrap", "Third message"
  end
end
