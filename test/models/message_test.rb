require "test_helper"

class MessageTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-account-messages")
    set_tenant(@account)
    @user = @account.users.create!(email: "user@example.com", password: "password123")
    @space = @account.spaces.create!(name: "Test Space")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    @conversation = @account.conversations.create!(council: @council, user: @user, title: "Test Conversation", space: @space)

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

  test "invalid without content" do
    message = @account.messages.new(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: ""
    )
    assert_not message.valid?
    assert_includes message.errors[:content], "can't be blank"
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
    space = @account.spaces.create!(name: "Advisor Sender Test Space")
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: space
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
    space = @account.spaces.create!(name: "Role Advisor Test Space")
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: space
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

  test "valid status values are pending, complete, error, and cancelled" do
    assert_equal({ "pending" => "pending", "complete" => "complete", "error" => "error", "cancelled" => "cancelled" }, Message.statuses)
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

  # Threading and Reply Tests
  test "belongs to parent_message for replies" do
    message = Message.new
    assert_respond_to message, :parent_message
  end

  test "has many replies" do
    message = Message.new
    assert_respond_to message, :replies
  end

  test "can create reply to message" do
    root_msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root message"
    )

    reply = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Reply message",
      parent_message: root_msg
    )

    assert_equal root_msg, reply.parent_message
    assert_includes root_msg.replies, reply
  end

  test "depth returns 0 for root message" do
    root_msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root message"
    )

    assert_equal 0, root_msg.depth
  end

  test "depth returns correct level for nested replies" do
    root_msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root message"
    )

    level1 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Level 1",
      parent_message: root_msg
    )

    level2 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Level 2",
      parent_message: level1
    )

    assert_equal 0, root_msg.depth
    assert_equal 1, level1.depth
    assert_equal 2, level2.depth
  end

  test "root_message? returns true for root messages" do
    root_msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root message"
    )

    assert root_msg.root_message?
  end

  test "root_message? returns false for replies" do
    root_msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root message"
    )

    reply = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Reply",
      parent_message: root_msg
    )

    assert_not reply.root_message?
  end

  test "root_messages scope returns only root messages" do
    root_msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root message"
    )

    reply = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Reply",
      parent_message: root_msg
    )

    root_messages = Message.root_messages
    assert_includes root_messages, root_msg
    assert_not_includes root_messages, reply
  end

  # Pending Advisor Tests
  test "pending_advisor_ids defaults to empty array" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )

    assert_equal [], msg.pending_advisor_ids
    assert msg.solved?
  end

  test "solved? returns false when pending_advisor_ids has values" do
    space = @account.spaces.create!(name: "Pending Test Space")
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: space
    )

    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: [ advisor.id ]
    )

    assert_not msg.solved?
  end

  test "pending_for? returns true for advisor in pending list" do
    space = @account.spaces.create!(name: "Pending Test Space")
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: space
    )

    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: [ advisor.id ]
    )

    assert msg.pending_for?(advisor.id)
  end

  test "resolve_for_advisor! removes advisor from pending list" do
    space = @account.spaces.create!(name: "Pending Test Space")
    advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model,
      space: space
    )

    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: [ advisor.id ]
    )

    msg.resolve_for_advisor!(advisor.id)

    assert msg.solved?
    assert_not msg.pending_for?(advisor.id)
  end

  # Command Detection Tests
  test "command? returns true for messages starting with slash" do
    msg = @account.messages.new(content: "/invite @advisor")
    assert msg.command?
  end

  test "command? returns false for regular messages" do
    msg = @account.messages.new(content: "Hello everyone")
    assert_not msg.command?
  end

  # Mention Parsing Tests
  test "mentions extracts @mentions from content" do
    msg = @account.messages.new(content: "@advisor1 and @advisor-2 please help")
    assert_equal [ "advisor1", "advisor-2" ], msg.mentions
  end

  test "mentions does not parse underscore handles" do
    msg = @account.messages.new(content: "@advisor_name and @advisor-name")
    assert_equal [ "advisor-name" ], msg.mentions
  end

  test "mentions does not partially parse invalid handle tokens" do
    msg = @account.messages.new(content: "@data_science and @data-science")
    assert_equal [ "data-science" ], msg.mentions
  end

  test "mentions returns empty array for content without mentions" do
    msg = @account.messages.new(content: "Hello everyone")
    assert_equal [], msg.mentions
  end

  test "mentions_all? returns true for @all mention" do
    msg = @account.messages.new(content: "@all what do you think?")
    assert msg.mentions_all?
  end

  test "mentions_all? returns true for @everyone mention" do
    msg = @account.messages.new(content: "@everyone please respond")
    assert msg.mentions_all?
  end

  test "mentions_all? returns false without @all or @everyone" do
    msg = @account.messages.new(content: "Hello @advisor")
    assert_not msg.mentions_all?
  end
end
