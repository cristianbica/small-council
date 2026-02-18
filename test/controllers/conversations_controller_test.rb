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
end
