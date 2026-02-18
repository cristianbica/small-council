require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
  end

  test "should redirect to sign in when not authenticated for index" do
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    get council_conversations_url(council)
    assert_redirected_to sign_in_url
  end

  test "should redirect to sign in when not authenticated for show" do
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test")
    get conversation_url(conversation)
    assert_redirected_to sign_in_url
  end

  test "should redirect to sign in when not authenticated for new" do
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    get new_council_conversation_url(council)
    assert_redirected_to sign_in_url
  end

  test "should redirect to sign in when not authenticated for create" do
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    post council_conversations_url(council), params: { conversation: { title: "Test" } }
    assert_redirected_to sign_in_url
  end

  test "index shows conversations for council" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test Conversation")

    get council_conversations_url(council)
    assert_response :success
    assert_select "h1", "Conversations"
    assert_select "h3", conversation.title
  end

  test "show displays conversation with messages" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test Conversation")
    message = @account.messages.create!(
      conversation: conversation,
      sender: @user,
      role: "user",
      content: "Test message content"
    )

    get conversation_url(conversation)
    assert_response :success
    assert_select "h1", conversation.title
    assert_select ".whitespace-pre-wrap", message.content
  end

  test "new renders form" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    get new_council_conversation_url(council)
    assert_response :success
    assert_select "form[action=?]", council_conversations_path(council)
    assert_select "input[name=?]", "conversation[title]"
  end

  test "create makes conversation with first message" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    assert_difference("Conversation.count", 1) do
      assert_difference("Message.count", 1) do
        post council_conversations_url(council), params: {
          conversation: { title: "New Conversation Topic" }
        }
      end
    end

    conversation = Conversation.last
    assert_equal "New Conversation Topic", conversation.title
    assert_equal @user, conversation.user
    assert_equal council, conversation.council

    message = Message.last
    assert_equal conversation, message.conversation
    assert_equal @user, message.sender
    assert_equal "user", message.role
    assert_equal "New Conversation Topic", message.content

    assert_redirected_to conversation_url(conversation)
  end

  test "create redirects to conversation on success" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    post council_conversations_url(council), params: {
      conversation: { title: "Test" }
    }
    assert_redirected_to conversation_url(Conversation.last)
  end

  test "create renders new on failure" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    post council_conversations_url(council), params: {
      conversation: { title: "" }
    }
    assert_response :unprocessable_entity
    assert_select "h1", "Start New Conversation"
  end

  test "update redirects on success" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Old Title")

    patch conversation_url(conversation), params: {
      conversation: { title: "Updated Title" }
    }
    assert_redirected_to conversation_url(conversation)
    assert_equal "Updated Title", conversation.reload.title
  end

  test "update redirects on failure" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Old Title")

    patch conversation_url(conversation), params: {
      conversation: { title: "" }
    }
    # Controller redirects on failure with alert
    assert_redirected_to conversation_url(conversation)
    assert_equal "Old Title", conversation.reload.title
  end

  test "redirects when conversation belongs to different account" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create another account and conversation
    other_account = Account.create!(name: "Other Account", slug: "other-account")
    other_user = other_account.users.create!(email: "other@example.com", password: "password123")
    other_council = other_account.councils.create!(name: "Other Council", user: other_user, space: other_account.spaces.create!(name: "Other Space"))
    other_conversation = other_account.conversations.create!(council: other_council, user: other_user, title: "Other Conversation")

    get conversation_url(other_conversation)
    # Controller redirects when RecordNotFound or wrong space
    assert_redirected_to space_councils_path(@account.spaces.first)
  end

  test "redirects when council belongs to different space" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create council in another space
    other_space = @account.spaces.create!(name: "Other Space")
    other_council = @account.councils.create!(name: "Other Council", user: @user, space: other_space)

    # Try to access council from current space context
    get council_conversations_url(other_council)
    # Should redirect because council is not in Current.space
    assert_redirected_to space_councils_path(@space)
    assert_equal "Council not found.", flash[:alert]
  end

  test "update changes rules of engagement" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test", rules_of_engagement: :round_robin)

    patch conversation_url(conversation), params: {
      conversation: { rules_of_engagement: :consensus }
    }
    assert_redirected_to conversation_url(conversation)
    assert_equal "consensus", conversation.reload.rules_of_engagement
  end

  test "show redirects when conversation belongs to different space" do
    sign_in_as(@user)
    set_tenant(@account)

    other_space = @account.spaces.create!(name: "Other Space")
    other_council = @account.councils.create!(name: "Other Council", user: @user, space: other_space)
    other_conversation = @account.conversations.create!(council: other_council, user: @user, title: "Test")

    get conversation_url(other_conversation)
    assert_redirected_to space_councils_path(@space)
    assert_equal "Conversation not found.", flash[:alert]
  end

  # ============================================================================
  # SECURITY TESTS - Added as part of security audit
  # ============================================================================

  test "cannot access conversation from different account via direct URL" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create resources in other account
    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Conv Account", slug: "other-conv-acct")
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
      other_account.conversations.create!(council: other_council, user: other_user, title: "Other Conv")
    end

    # Try to access other account's conversation
    # Conversation won't be found in Current.account scope -> 404
    get conversation_url(other_conversation)
    assert_response :not_found
  end

  test "cannot update conversation from different account" do
    sign_in_as(@user)
    set_tenant(@account)

    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Update Account", slug: "other-update-acct")
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
      other_account.conversations.create!(council: other_council, user: other_user, title: "Other Conv")
    end

    # Try to update other account's conversation
    # The conversation won't be found in Current.account scope
    patch conversation_url(other_conversation), params: {
      conversation: { title: "Hacked Title" }
    }

    # Should get 404
    assert_response :not_found

    # Verify title wasn't changed
    ActsAsTenant.without_tenant do
      assert_equal "Other Conv", other_conversation.reload.title
    end
  end

  test "cannot manipulate account_id via conversation form" do
    sign_in_as(@user)
    set_tenant(@account)

    other_account = accounts(:two)

    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    assert_difference("Conversation.count") do
      post council_conversations_url(council), params: {
        conversation: {
          title: "Test Conversation",
          account_id: other_account.id  # Attempting to set account
        }
      }
    end

    conversation = Conversation.last
    assert_equal @account.id, conversation.account_id
    refute_equal other_account.id, conversation.account_id
  end

  test "cannot manipulate user_id via conversation form" do
    sign_in_as(@user)
    set_tenant(@account)

    other_user = @account.users.create!(email: "other-user@example.com", password: "password123")

    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    assert_difference("Conversation.count") do
      post council_conversations_url(council), params: {
        conversation: {
          title: "Test Conversation",
          user_id: other_user.id  # Attempting to set different user
        }
      }
    end

    conversation = Conversation.last
    assert_equal @user.id, conversation.user_id
    refute_equal other_user.id, conversation.user_id
  end

  test "index only shows conversations from current council" do
    sign_in_as(@user)
    set_tenant(@account)

    # Create two councils with conversations
    council1 = @account.councils.create!(name: "Council 1", user: @user, space: @space)
    council2 = @account.councils.create!(name: "Council 2", user: @user, space: @space)

    conv1 = @account.conversations.create!(council: council1, user: @user, title: "Conv in Council 1")
    conv2 = @account.conversations.create!(council: council2, user: @user, title: "Conv in Council 2")

    # View conversations in council1
    get council_conversations_url(council1)
    assert_response :success
    assert_select "h3", text: "Conv in Council 1"
    assert_select "h3", { text: "Conv in Council 2", count: 0 }
  end

  test "cannot list conversations from different council via ID manipulation" do
    sign_in_as(@user)
    set_tenant(@account)

    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Council Account", slug: "other-council-acct")
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

    # Try to access conversations from other account's council
    # Council won't be found in Current.account scope
    get council_conversations_url(other_council)
    # The controller redirects when council is not found in Current.space
    assert_redirected_to space_councils_path(@space)
    assert_equal "Council not found.", flash[:alert]
  end
end
