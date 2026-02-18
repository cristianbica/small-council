require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = accounts(:one)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
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
end
