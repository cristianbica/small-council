require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
  end

  test "should redirect to sign in when not authenticated for index" do
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user)
    get council_conversations_url(council)
    assert_redirected_to sign_in_url
  end

  test "should redirect to sign in when not authenticated for show" do
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test")
    get conversation_url(conversation)
    assert_redirected_to sign_in_url
  end

  test "should redirect to sign in when not authenticated for new" do
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user)
    get new_council_conversation_url(council)
    assert_redirected_to sign_in_url
  end

  test "should redirect to sign in when not authenticated for create" do
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user)
    post council_conversations_url(council), params: { conversation: { title: "Test" } }
    assert_redirected_to sign_in_url
  end

  test "index shows conversations for council" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user)
    conversation = @account.conversations.create!(council: council, user: @user, title: "Test Conversation")

    get council_conversations_url(council)
    assert_response :success
    assert_select "h1", "Conversations"
    assert_select "h3", conversation.title
  end

  test "show displays conversation with messages" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user)
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
    council = @account.councils.create!(name: "Test Council", user: @user)

    get new_council_conversation_url(council)
    assert_response :success
    assert_select "form[action=?]", council_conversations_path(council)
    assert_select "input[name=?]", "conversation[title]"
  end

  test "create makes conversation with first message" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user)

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
    council = @account.councils.create!(name: "Test Council", user: @user)

    post council_conversations_url(council), params: {
      conversation: { title: "Test" }
    }
    assert_redirected_to conversation_url(Conversation.last)
  end

  test "create renders new on failure" do
    sign_in_as(@user)
    set_tenant(@account)
    council = @account.councils.create!(name: "Test Council", user: @user)

    post council_conversations_url(council), params: {
      conversation: { title: "" }
    }
    assert_response :unprocessable_entity
    assert_select "h1", "Start New Conversation"
  end
end
