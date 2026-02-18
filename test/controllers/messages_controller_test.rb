require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")

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
  end

  test "should redirect to sign in when not authenticated" do
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test")

    post conversation_messages_url(conversation), params: { message: { content: "Test" } }
    assert_redirected_to sign_in_url
  end

  test "create adds message to conversation" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test")

    assert_difference("Message.count", 1) do
      post conversation_messages_url(conversation), params: {
        message: { content: "New message content" }
      }
    end

    message = Message.last
    assert_equal conversation, message.conversation
    assert_equal @user, message.sender
    assert_equal "user", message.role
    assert_equal "New message content", message.content
  end

  test "create redirects to conversation" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test")

    post conversation_messages_url(conversation), params: {
      message: { content: "New message content" }
    }
    assert_redirected_to conversation_url(conversation)
  end

  test "create fails with invalid content" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test")

    assert_no_difference("Message.count") do
      post conversation_messages_url(conversation), params: {
        message: { content: "" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create enqueues jobs for responding advisors" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model
    )
    council.advisors << advisor
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test")

    assert_enqueued_jobs 1, only: GenerateAdvisorResponseJob do
      post conversation_messages_url(conversation), params: {
        message: { content: "Hello advisor" }
      }
    end
  end

  test "create adds pending message for each responder" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model
    )
    council.advisors << advisor
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test")

    # 1 user message + 1 pending advisor message
    assert_difference("Message.count", 2) do
      post conversation_messages_url(conversation), params: {
        message: { content: "Hello advisor" }
      }
    end

    pending = conversation.messages.last
    assert_equal "pending", pending.status
    assert_equal advisor, pending.sender
    assert_match(/thinking/, pending.content)
  end
end
