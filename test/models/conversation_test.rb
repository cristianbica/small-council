require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-account-conversations")
    set_tenant(@account)
    @user = @account.users.create!(email: "user@example.com", password: "password123")
    @council = @account.councils.create!(name: "Test Council", user: @user)
  end

  # Validation tests
  test "valid with account, council, user, and title" do
    conversation = @account.conversations.new(council: @council, user: @user, title: "Test")
    assert conversation.valid?
  end

  test "invalid without title" do
    conversation = @account.conversations.new(council: @council, user: @user)
    assert_not conversation.valid?
    assert_includes conversation.errors[:title], "can't be blank"
  end

  test "invalid without account" do
    ActsAsTenant.without_tenant do
      conversation = Conversation.new(council: @council, user: @user, title: "Test")
      assert_not conversation.valid?
      assert_includes conversation.errors[:account], "can't be blank"
    end
  end

  test "invalid without council" do
    conversation = @account.conversations.new(user: @user, title: "Test")
    assert_not conversation.valid?
    assert_includes conversation.errors[:council], "can't be blank"
  end

  test "invalid without user" do
    conversation = @account.conversations.new(council: @council, title: "Test")
    assert_not conversation.valid?
    assert_includes conversation.errors[:user], "can't be blank"
  end

  # Association tests
  test "belongs to account" do
    conversation = Conversation.new
    assert_respond_to conversation, :account
  end

  test "belongs to council" do
    conversation = Conversation.new
    assert_respond_to conversation, :council
  end

  test "belongs to user" do
    conversation = Conversation.new
    assert_respond_to conversation, :user
  end

  test "has many messages" do
    conversation = Conversation.new
    assert_respond_to conversation, :messages
  end

  test "dependent destroy removes associated messages" do
    conversation = @account.conversations.create!(council: @council, user: @user, title: "Test")
    conversation.messages.create!(
      sender: @user,
      role: "user",
      content: "Test message",
      account: @account
    )
    assert_difference("Message.count", -1) do
      conversation.destroy
    end
  end

  # Enum tests
  test "defaults to active status" do
    conversation = @account.conversations.create!(council: @council, user: @user, title: "Test")
    assert_equal "active", conversation.status
    assert conversation.active?
  end

  test "can be set to archived status" do
    conversation = @account.conversations.create!(council: @council, user: @user, title: "Test", status: "archived")
    assert_equal "archived", conversation.status
    assert conversation.archived?
  end

  test "status enum methods work" do
    conversation = @account.conversations.create!(council: @council, user: @user, title: "Test")
    assert conversation.active?
    assert_not conversation.archived?

    conversation.archived!
    assert conversation.archived?
    assert_not conversation.active?
  end

  test "invalid status raises ArgumentError" do
    assert_raises(ArgumentError) do
      @account.conversations.create!(council: @council, user: @user, title: "Test", status: "deleted")
    end
  end

  test "valid status values are active and archived" do
    assert_equal({ "active" => "active", "archived" => "archived" }, Conversation.statuses)
  end

  # Scope tests
  test "recent scope orders by last_message_at descending" do
    conv1 = @account.conversations.create!(council: @council, user: @user, title: "Conv 1", last_message_at: 1.hour.ago)
    conv2 = @account.conversations.create!(council: @council, user: @user, title: "Conv 2", last_message_at: 1.minute.ago)
    conv3 = @account.conversations.create!(council: @council, user: @user, title: "Conv 3", last_message_at: 1.day.ago)

    ordered = Conversation.recent.to_a
    assert_equal [ conv2, conv1, conv3 ], ordered
  end

  test "recent scope handles nil last_message_at" do
    conv1 = @account.conversations.create!(council: @council, user: @user, title: "Conv 1", last_message_at: 1.hour.ago)
    conv2 = @account.conversations.create!(council: @council, user: @user, title: "Conv 2", last_message_at: nil)

    ordered = Conversation.recent.to_a
    # nil values typically sort last in descending order in PostgreSQL
    assert_includes ordered, conv1
    assert_includes ordered, conv2
  end

  test "active scope returns only active conversations" do
    active_conv = @account.conversations.create!(council: @council, user: @user, title: "Active", status: "active")
    archived_conv = @account.conversations.create!(council: @council, user: @user, title: "Archived", status: "archived")

    actives = Conversation.active.to_a
    assert_includes actives, active_conv
    assert_not_includes actives, archived_conv
  end

  test "active scope excludes archived conversations" do
    @account.conversations.create!(council: @council, user: @user, title: "Archived", status: "archived")
    assert_empty Conversation.active
  end
end
