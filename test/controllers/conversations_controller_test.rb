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
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test", space: @space)
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
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test Conversation", space: @space)

    get council_conversations_url(council)
    assert_response :success
    assert_select "h1", "#{council.name} Conversations"
    assert_select "h3", conversation.title
    assert_select "button[title='Conversation actions']", minimum: 1
    assert_select "button", text: "Archive", minimum: 1
  end

  test "index hides archive action when user cannot delete conversation" do
    sign_in_as(@user)
    set_tenant(@account)
    council_creator = @account.users.create!(email: "list-council-creator@example.com", password: "password123")
    conversation_owner = @account.users.create!(email: "list-conversation-owner@example.com", password: "password123")
    council = @account.councils.create!(name: "Restricted Council", user: council_creator, space: @space)
    @account.conversations.create!(council: council, user: conversation_owner, title: "Hidden Actions", space: @space)

    get council_conversations_url(council)

    assert_response :success
    assert_select "button", text: "Archive", count: 0
  end

  test "show displays conversation with messages" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test Conversation", space: @space)
    message = @account.messages.create!(
      conversation: conversation,
      sender: @user,
      role: "user",
      content: "Test message content"
    )

    get conversation_url(conversation)
    assert_response :success
    assert_select "h1", text: conversation.title
    assert_select "label[title='Edit conversation title']", count: 1
    assert_select ".whitespace-pre-wrap", message.content
  end

  test "show adhoc displays actions menu with archive and delete for conversation owner" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation = @account.conversations.create!(
      user: @user,
      title: "Owner Adhoc Conversation",
      conversation_type: :adhoc,
      status: :active,
      space: @space
    )

    get conversation_url(conversation)

    assert_response :success
    assert_select "button[title='Conversation actions']", minimum: 1
    assert_select "button", text: "Archive", minimum: 1
    assert_select "button", text: "Delete", minimum: 1
  end

  test "show adhoc hides actions when user cannot delete conversation" do
    sign_in_as(@user)
    set_tenant(@account)

    conversation_owner = @account.users.create!(email: "adhoc-owner@example.com", password: "password123")
    conversation = @account.conversations.create!(
      user: conversation_owner,
      title: "Restricted Adhoc Conversation",
      conversation_type: :adhoc,
      status: :active,
      space: @space
    )

    get conversation_url(conversation)

    assert_response :success
    assert_select "button", text: "Archive", count: 0
    assert_select "button", text: "Delete", count: 0
  end

  test "archive sets conversation status to archived" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Archive Me", space: @space)

    post archive_conversation_url(conversation)

    assert_redirected_to conversation_url(conversation)
    assert_equal "archived", conversation.reload.status
    assert_equal "Conversation archived.", flash[:notice]
  end

  test "archive fails for unauthorized users" do
    sign_in_as(@user)
    set_tenant(@account)
    other_user = @account.users.create!(email: "archive-other@example.com", password: "password123")
    other_council_creator = @account.users.create!(email: "archive-creator@example.com", password: "password123")
    council = @account.councils.create!(name: "Restricted Council", user: other_council_creator, space: @space)
    conversation = @account.conversations.create!(
      council: council,
      user: other_user,
      title: "Cannot Archive",
      space: @space
    )

    post archive_conversation_url(conversation)

    assert_redirected_to conversation_url(conversation)
    assert_equal "active", conversation.reload.status
    assert_equal "You are not authorized to archive this conversation.", flash[:alert]
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

  test "create makes conversation without seeded message" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    assert_difference("Conversation.count", 1) do
      assert_no_difference("Message.count") do
        post council_conversations_url(council), params: {
          conversation: {
            title: "New Conversation Topic",
            rules_of_engagement: "round_robin"
          }
        }
      end
    end

    conversation = Conversation.last
    assert_equal "New Conversation Topic", conversation.title
    assert_equal "round_robin", conversation.rules_of_engagement
    assert_equal @user, conversation.user
    assert_equal council, conversation.council

    assert_redirected_to conversation_url(conversation)
  end

  test "create redirects to conversation on success" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    post council_conversations_url(council), params: {
      conversation: {
        title: "Test",
        rules_of_engagement: "round_robin"
      }
    }
    assert_redirected_to conversation_url(Conversation.last)
  end

  test "create renders new on failure" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    post council_conversations_url(council), params: {
      conversation: {
        title: "",
        rules_of_engagement: ""
      }
    }
    assert_response :unprocessable_entity
    assert_select "h1", "Start Meeting"
  end

  test "update redirects on success" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Old Title", space: @space)

    patch conversation_url(conversation), params: {
      conversation: { title: "Updated Title" }
    }
    assert_redirected_to conversation_url(conversation)
    assert_equal "Updated Title", conversation.reload.title
    assert conversation.title_locked?
  end

  test "update redirects on failure" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Old Title", space: @space)

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
    other_space = other_account.spaces.create!(name: "Other Space")
    other_council = other_account.councils.create!(name: "Other Council", user: other_user, space: other_space)
    other_conversation = other_account.conversations.create!(council: other_council, user: other_user, title: "Other Conversation", space: other_space)

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
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test", roe_type: :open, space: @space)

    patch conversation_url(conversation), params: {
      conversation: { roe_type: :consensus }
    }
    assert_redirected_to conversation_url(conversation)
    assert_equal "consensus", conversation.reload.roe_type
  end

  test "show redirects when conversation belongs to different space" do
    sign_in_as(@user)
    set_tenant(@account)

    other_space = @account.spaces.create!(name: "Other Space")
    other_council = @account.councils.create!(name: "Other Council", user: @user, space: other_space)
    other_conversation = @account.conversations.create!(council: other_council, user: @user, title: "Test", space: other_space)

    get conversation_url(other_conversation)
    assert_redirected_to space_councils_path(@space)
    assert_equal "Conversation not found.", flash[:alert]
  end

  test "invite_advisor redirects when conversation belongs to different space" do
    sign_in_as(@user)
    set_tenant(@account)

    advisor = @account.advisors.create!(name: "Test Advisor", system_prompt: "Help", space: @space)
    other_space = @account.spaces.create!(name: "Other Space")
    other_council = @account.councils.create!(name: "Other Council", user: @user, space: other_space)
    other_conversation = @account.conversations.create!(
      council: other_council,
      user: @user,
      title: "Other Space Conv",
      space: other_space
    )

    post invite_advisor_conversation_path(other_conversation), params: {
      advisor_id: advisor.id
    }

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
      other_account.conversations.create!(council: other_council, user: other_user, title: "Other Conv", space: other_space)
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
      other_account.conversations.create!(council: other_council, user: other_user, title: "Other Conv", space: other_space)
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
          rules_of_engagement: "round_robin",
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
          rules_of_engagement: "round_robin",
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

    conv1 = @account.conversations.create!(council: council1, user: @user, title: "Conv in Council 1", space: @space)
    conv2 = @account.conversations.create!(council: council2, user: @user, title: "Conv in Council 2", space: @space)

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

  # ============================================================================
  # DELETE TESTS
  # ============================================================================

  test "destroy deletes conversation for conversation starter" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(
      council: council,
      user: @user,
      title: "Test Conversation",
      space: @space
    )

    assert_difference("Conversation.count", -1) do
      delete conversation_url(conversation)
    end

    assert_redirected_to council_conversations_path(council)
    assert_equal "Conversation deleted successfully.", flash[:notice]
  end

  test "destroy allows council creator who is not conversation starter" do
    sign_in_as(@user)
    set_tenant(@account)
    other_user = @account.users.create!(email: "other@example.com", password: "password123")
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(
      council: council,
      user: other_user,
      title: "Test Conversation",
      space: @space
    )

    assert_difference("Conversation.count", -1) do
      delete conversation_url(conversation)
    end

    assert_redirected_to council_conversations_path(council)
    assert_equal "Conversation deleted successfully.", flash[:notice]
  end

  test "destroy fails for unauthorized users" do
    sign_in_as(@user)
    set_tenant(@account)
    other_user = @account.users.create!(email: "other@example.com", password: "password123")
    other_council_creator = @account.users.create!(email: "creator@example.com", password: "password123")
    council = @account.councils.create!(name: "Test Council", user: other_council_creator, space: @space)
    conversation = @account.conversations.create!(
      council: council,
      user: other_user,
      title: "Test Conversation",
      space: @space
    )

    assert_no_difference("Conversation.count") do
      delete conversation_url(conversation)
    end

    assert_redirected_to conversation_url(conversation)
    assert_equal "You are not authorized to delete this conversation.", flash[:alert]
  end

  test "destroy requires authentication" do
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(
      council: council,
      user: @user,
      title: "Test Conversation",
      space: @space
    )

    delete conversation_url(conversation)
    assert_redirected_to sign_in_url
  end

  test "destroy handles turbo_stream format with redirect" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    conversation = @account.conversations.create!(
      council: council,
      user: @user,
      title: "Test Conversation",
      space: @space
    )

    assert_difference("Conversation.count", -1) do
      delete conversation_url(conversation), as: :turbo_stream
    end

    assert_redirected_to council_conversations_path(council)
  end
end
