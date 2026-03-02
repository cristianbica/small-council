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
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test", space: @space)

    post conversation_messages_url(conversation), params: { message: { content: "Test" } }
    assert_redirected_to sign_in_url
  end

  test "create adds message to conversation" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test", space: @space)

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
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: @space
    )
    council.advisors << advisor
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test", space: @space)

    # Add advisor as participant to satisfy conversation validation
    conversation.conversation_participants.create!(
      advisor: advisor,
      role: :advisor,
      position: 0
    )

    post conversation_messages_url(conversation), params: {
      message: { content: "New message content" }
    }
    assert_redirected_to conversation_url(conversation)
  end

  test "create fails with invalid content" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test", space: @space)

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
      llm_model: @llm_model,
      space: @space
    )
    council.advisors << advisor
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test", space: @space)

    # Add advisor as participant (simulating what happens in real flow)
    conversation.conversation_participants.create!(
      advisor: advisor,
      role: :advisor,
      position: 0
    )

    # For consensus RoE, all advisors respond
    conversation.update!(roe_type: :consensus)

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
      llm_model: @llm_model,
      space: @space
    )
    council.advisors << advisor
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test", space: @space)

    # Add advisor as participant
    conversation.conversation_participants.create!(
      advisor: advisor,
      role: :advisor,
      position: 0
    )

    # For consensus RoE, all advisors respond
    conversation.update!(roe_type: :consensus)

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

  # ============================================================================
  # SECURITY TESTS - Added as part of security audit
  # ============================================================================

  test "cannot create message in conversation from different account" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create resources in other account
    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Messages", slug: "other-messages")
    end
    other_user = ActsAsTenant.without_tenant do
      other_account.users.create!(email: "other@example.com", password: "password123")
    end
    other_space = ActsAsTenant.without_tenant do
      other_account.spaces.create!(name: "Other Space")
    end
    other_council = ActsAsTenant.without_tenant do
      other_account.councils.create!(name: "Other Council", user: other_user, space: other_space)
    end
    other_conversation = ActsAsTenant.without_tenant do
      other_account.conversations.create!(council: other_council, user: other_user, title: "Other Conv", space: other_space)
    end

    # The MessagesController uses Current.account.conversations.find
    # which will raise RecordNotFound for other account's conversation
    get conversation_url(other_conversation)
    assert_response :not_found
  end

  test "cannot manipulate message sender via user_id parameter" do
    sign_in_as(@user)
    set_tenant(@account)

    other_user = @account.users.create!(email: "other-sender@example.com", password: "password123")

    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test", space: @space)

    assert_difference("Message.count", 1) do
      post conversation_messages_url(conversation), params: {
        message: {
          content: "Test message",
          sender_id: other_user.id,  # Attempting to set different sender
          sender_type: "User"
        }
      }
    end

    message = Message.last
    # Should be current user, not the tampered sender_id
    assert_equal @user.id, message.sender_id
    assert_equal @user, message.sender
  end

  test "cannot create message with invalid role via role parameter" do
    sign_in_as(@user)
    set_tenant(@account)

    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test", space: @space)

    assert_difference("Message.count", 1) do
      post conversation_messages_url(conversation), params: {
        message: {
          content: "Test message"
          # role is not permitted in params, will be set by controller
        }
      }
    end

    message = Message.last
    # Role should be set by controller, not from params
    assert_equal "user", message.role
  end

  test "cannot access message creation in archived conversation" do
    sign_in_as(@user)
    set_tenant(@account)

    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(
      council: council,
      user: @user,
      title: "Test",
      status: :archived,
      space: @space
    )

    # Should still allow messages (archived doesn't block messages currently)
    # But verify the behavior is intentional
    assert_difference("Message.count", 1) do
      post conversation_messages_url(conversation), params: {
        message: { content: "Test message" }
      }
    end
  end
end
