require "test_helper"

class MessageTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-account-messages")
    set_tenant(@account)
    @user = @account.users.create!(email: "user@example.com", password: "password123")
    @council = @account.councils.create!(name: "Test Council", user: @user)
    @conversation = @account.conversations.create!(council: @council, user: @user)
  end

  # Validation tests
  test "valid with all required attributes" do
    message = @account.messages.new(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test message"
    )
    assert message.valid?
  end

  test "invalid without account" do
    ActsAsTenant.without_tenant do
      message = Message.new(
        conversation: @conversation,
        sender: @user,
        role: "user",
        content: "Test message"
      )
      assert_not message.valid?
      assert_includes message.errors[:account], "can't be blank"
    end
  end

  test "invalid without conversation" do
    message = @account.messages.new(
      sender: @user,
      role: "user",
      content: "Test message"
    )
    assert_not message.valid?
    assert_includes message.errors[:conversation], "can't be blank"
  end

  test "invalid without sender" do
    message = @account.messages.new(
      conversation: @conversation,
      role: "user",
      content: "Test message"
    )
    assert_not message.valid?
    assert_includes message.errors[:sender], "can't be blank"
  end

  test "invalid without role" do
    message = @account.messages.new(
      conversation: @conversation,
      sender: @user,
      content: "Test message"
    )
    assert_not message.valid?
    assert_includes message.errors[:role], "can't be blank"
  end

  # Association tests
  test "belongs to account" do
    message = Message.new
    assert_respond_to message, :account
  end

  test "belongs to conversation" do
    message = Message.new
    assert_respond_to message, :conversation
  end

  test "belongs to sender as polymorphic association" do
    message = Message.new
    assert_respond_to message, :sender
    assert_respond_to message, :sender_type
    assert_respond_to message, :sender_id
  end

  test "sender can be a User" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test from user"
    )
    assert_equal @user, message.sender
    assert_equal "User", message.sender_type
  end

  test "sender can be an Advisor" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    message = @account.messages.create!(
      conversation: @conversation,
      sender: advisor,
      role: "advisor",
      content: "Test from advisor"
    )
    assert_equal advisor, message.sender
    assert_equal "Advisor", message.sender_type
  end

  test "has one usage_record" do
    message = Message.new
    assert_respond_to message, :usage_record
  end

  test "dependent destroy removes associated usage_record" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test message"
    )
    message.create_usage_record!(
      account: @account,
      provider: "openai",
      model: "gpt-4",
      input_tokens: 10,
      output_tokens: 20,
      cost_cents: 5
    )
    assert_difference("UsageRecord.count", -1) do
      message.destroy
    end
  end

  # Role enum tests
  test "role enum values" do
    assert_equal({ "user" => "user", "advisor" => "advisor", "system" => "system" }, Message.roles)
  end

  test "can set role to user" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert message.user?
  end

  test "can set role to advisor" do
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      model_provider: "openai",
      model_id: "gpt-4"
    )
    message = @account.messages.create!(
      conversation: @conversation,
      sender: advisor,
      role: "advisor",
      content: "Test"
    )
    assert message.advisor?
  end

  test "can set role to system" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "system",
      content: "System message"
    )
    assert message.system?
  end

  test "role enum methods work" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert message.user?
    assert_not message.advisor?

    message.advisor!
    assert message.advisor?
    assert_not message.user?
  end

  test "invalid role raises ArgumentError" do
    assert_raises(ArgumentError) do
      @account.messages.create!(
        conversation: @conversation,
        sender: @user,
        role: "invalid_role",
        content: "Test"
      )
    end
  end

  # Status enum tests
  test "defaults to complete status" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert_equal "complete", message.status
    assert message.complete?
  end

  test "can set status to pending" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      status: "pending"
    )
    assert message.pending?
  end

  test "can set status to error" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      status: "error"
    )
    assert message.error?
  end

  test "status enum methods work" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert message.complete?
    assert_not message.pending?

    message.pending!
    assert message.pending?
    assert_not message.complete?
  end

  test "invalid status raises ArgumentError" do
    assert_raises(ArgumentError) do
      @account.messages.create!(
        conversation: @conversation,
        sender: @user,
        role: "user",
        content: "Test",
        status: "invalid_status"
      )
    end
  end

  test "valid status values are pending, complete, and error" do
    assert_equal({ "pending" => "pending", "complete" => "complete", "error" => "error" }, Message.statuses)
  end

  # Scope tests
  test "by_role scope filters messages by role" do
    user_msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "User message"
    )
    system_msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "system",
      content: "System message"
    )

    user_messages = Message.by_role("user")
    assert_includes user_messages, user_msg
    assert_not_includes user_messages, system_msg
  end

  test "chronological scope orders by created_at ascending" do
    msg1 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "First",
      created_at: 1.hour.ago
    )
    msg2 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Second",
      created_at: 1.minute.ago
    )
    msg3 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Third",
      created_at: 1.day.ago
    )

    ordered = Message.chronological.to_a
    assert_equal [ msg3, msg1, msg2 ], ordered
  end
end
