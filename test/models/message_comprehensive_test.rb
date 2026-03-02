# test/models/message_comprehensive_test.rb
require "test_helper"

class MessageComprehensiveTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-message-comprehensive")
    set_tenant(@account)
    @user = @account.users.create!(email: "user@example.com", password: "password123")
    @space = @account.spaces.create!(name: "Test Space")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    @conversation = @account.conversations.create!(
      title: "Test Conversation",
      user: @user,
      council: @council,
      space: @space
    )

    provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )
    @llm_model = provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )

    @advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor.",
      space: @space,
      llm_model: @llm_model
    )
  end

  # ============================================================================
  # VALIDATIONS
  # ============================================================================

  test "invalid without account" do
    ActsAsTenant.without_tenant do
      msg = Message.new(
        conversation: @conversation,
        sender: @user,
        role: "user",
        content: "Test"
      )
      assert_not msg.valid?
      assert_includes msg.errors[:account], "can't be blank"
    end
  end

  test "invalid without conversation" do
    msg = @account.messages.new(
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert_not msg.valid?
    assert_includes msg.errors[:conversation], "can't be blank"
  end

  test "invalid without sender" do
    msg = @account.messages.new(
      conversation: @conversation,
      role: "user",
      content: "Test"
    )
    assert_not msg.valid?
    assert_includes msg.errors[:sender], "can't be blank"
  end

  test "invalid without role" do
    msg = @account.messages.new(
      conversation: @conversation,
      sender: @user,
      content: "Test"
    )
    assert_not msg.valid?
    assert_includes msg.errors[:role], "can't be blank"
  end

  test "invalid without content" do
    msg = @account.messages.new(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: ""
    )
    assert_not msg.valid?
    assert_includes msg.errors[:content], "can't be blank"
  end

  test "invalid with nil content" do
    msg = @account.messages.new(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: nil
    )
    assert_not msg.valid?
    assert_includes msg.errors[:content], "can't be blank"
  end

  test "valid with all required attributes" do
    msg = @account.messages.new(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test message"
    )
    assert msg.valid?
  end

  # ============================================================================
  # ROLE ENUM METHODS
  # ============================================================================

  test "role defaults to nil (must be set)" do
    msg = @account.messages.new(
      conversation: @conversation,
      sender: @user,
      content: "Test"
    )
    assert_nil msg.role
  end

  test "user? returns true for user role" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert msg.user?
    assert_not msg.advisor?
    assert_not msg.system?
  end

  test "advisor? returns true for advisor role" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Test"
    )
    assert msg.advisor?
    assert_not msg.user?
    assert_not msg.system?
  end

  test "system? returns true for system role" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "system",
      content: "Test"
    )
    assert msg.system?
    assert_not msg.user?
    assert_not msg.advisor?
  end

  test "role can be changed" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert msg.user?

    msg.advisor!
    assert msg.advisor?

    msg.system!
    assert msg.system?
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

  # ============================================================================
  # STATUS ENUM METHODS
  # ============================================================================

  test "status defaults to complete" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert_equal "complete", msg.status
    assert msg.complete?
  end

  test "pending? returns true for pending status" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "system",
      content: "[Thinking...]",
      status: "pending"
    )
    assert msg.pending?
    assert_not msg.complete?
    assert_not msg.error?
    assert_not msg.cancelled?
  end

  test "complete? returns true for complete status" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      status: "complete"
    )
    assert msg.complete?
  end

  test "error? returns true for error status" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "[Error occurred]",
      status: "error"
    )
    assert msg.error?
  end

  test "cancelled? returns true for cancelled status" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "system",
      content: "[Cancelled]",
      status: "cancelled"
    )
    assert msg.cancelled?
  end

  test "status can be changed" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert msg.complete?

    msg.pending!
    assert msg.pending?

    msg.error!
    assert msg.error?

    msg.cancelled!
    assert msg.cancelled?
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

  # ============================================================================
  # SCOPES
  # ============================================================================

  test "solved scope returns messages with empty or null pending_advisor_ids" do
    root = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root message"
    )
    reply = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Reply",
      parent_message: root
    )

    roots = Message.root_messages.to_a
    assert_includes roots, root
    assert_not_includes roots, reply
  end

  # ============================================================================
  # THREADING AND DEPTH
  # ============================================================================

  test "depth returns 0 for root message" do
    root = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root"
    )
    assert_equal 0, root.depth
  end

  test "depth returns 1 for direct reply" do
    root = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root"
    )
    reply = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Reply",
      parent_message: root
    )
    assert_equal 1, reply.depth
  end

  test "depth returns 2 for nested reply" do
    root = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root"
    )
    level1 = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Level 1",
      parent_message: root
    )
    level2 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Level 2",
      parent_message: level1
    )
    assert_equal 2, level2.depth
  end

  test "depth returns 3 for deeply nested reply" do
    root = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root"
    )
    level1 = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Level 1",
      parent_message: root
    )
    level2 = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Level 2",
      parent_message: level1
    )
    level3 = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Level 3",
      parent_message: level2
    )
    assert_equal 3, level3.depth
  end

  test "root_message? returns true for root" do
    root = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root"
    )
    assert root.root_message?
  end

  test "root_message? returns false for reply" do
    root = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root"
    )
    reply = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Reply",
      parent_message: root
    )
    assert_not reply.root_message?
  end

  test "thread_messages returns all messages in thread" do
    root = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root"
    )
    reply1 = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Reply 1",
      parent_message: root
    )
    reply2 = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Reply 2",
      parent_message: root
    )
    nested = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Nested",
      parent_message: reply1
    )

    thread = root.thread_messages
    assert_includes thread, root
    assert_includes thread, reply1
    assert_includes thread, reply2
    assert_includes thread, nested
    assert_equal 4, thread.length
  end

  test "replies association works" do
    root = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root"
    )
    reply = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Reply",
      parent_message: root
    )

    assert_includes root.replies, reply
    assert_equal reply, root.replies.first
  end

  test "parent_message association works" do
    root = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Root"
    )
    reply = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Reply",
      parent_message: root
    )

    assert_equal root, reply.parent_message
  end

  # ============================================================================
  # PENDING ADVISOR METHODS
  # ============================================================================

  test "solved? returns true when pending_advisor_ids is empty array" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: []
    )
    assert msg.solved?
  end

  test "solved? returns true when pending_advisor_ids is nil" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: nil
    )
    assert msg.solved?
  end

  test "solved? returns false when pending_advisor_ids has values" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: [ @advisor.id ]
    )
    assert_not msg.solved?
  end

  test "pending_for? returns true when advisor is in pending list" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: [ @advisor.id ]
    )
    assert msg.pending_for?(@advisor.id)
  end

  test "pending_for? returns false when advisor is not in pending list" do
    other_advisor = @account.advisors.create!(
      name: "Other Advisor",
      system_prompt: "You are other.",
      space: @space,
      llm_model: @llm_model
    )
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: [ @advisor.id ]
    )
    assert_not msg.pending_for?(other_advisor.id)
  end

  test "pending_for? handles string vs integer advisor_id" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: [ @advisor.id.to_s ]
    )
    assert msg.pending_for?(@advisor.id)  # Integer
    assert msg.pending_for?(@advisor.id.to_s)  # String
  end

  test "resolve_for_advisor! removes advisor from pending list" do
    other_advisor = @account.advisors.create!(
      name: "Other Advisor",
      system_prompt: "You are other.",
      space: @space,
      llm_model: @llm_model
    )
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: [ @advisor.id, other_advisor.id ]
    )

    msg.resolve_for_advisor!(@advisor.id)

    assert_not msg.pending_for?(@advisor.id)
    assert msg.pending_for?(other_advisor.id)
    assert_not msg.solved?  # Still has other pending advisor
  end

  test "resolve_for_advisor! marks message solved when last advisor resolved" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: [ @advisor.id ]
    )

    msg.resolve_for_advisor!(@advisor.id)

    assert msg.solved?
    assert_empty msg.reload.pending_advisor_ids
  end

  test "resolve_for_advisor! handles string advisor_id" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: [ @advisor.id ]
    )

    msg.resolve_for_advisor!(@advisor.id.to_s)

    assert msg.solved?
  end

  test "resolve_for_advisor! handles nil pending_advisor_ids" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      pending_advisor_ids: nil
    )

    # Should not raise error
    assert_nothing_raised do
      msg.resolve_for_advisor!(@advisor.id)
    end
  end

  # ============================================================================
  # COMMAND METHODS
  # ============================================================================

  test "command? returns true for command messages" do
    msg = @account.messages.new(content: "/invite @advisor")
    assert msg.command?
  end

  test "command? returns false for regular messages" do
    msg = @account.messages.new(content: "Hello everyone")
    assert_not msg.command?
  end

  test "command? returns false for nil content" do
    msg = @account.messages.new(content: nil)
    assert_not msg.command?
  end

  test "command? returns false for empty content" do
    msg = @account.messages.new(content: "")
    assert_not msg.command?
  end

  # ============================================================================
  # MENTION METHODS
  # ============================================================================

  test "mentions extracts single mention" do
    msg = @account.messages.new(content: "@advisor help me")
    assert_equal [ "advisor" ], msg.mentions
  end

  test "mentions extracts multiple mentions" do
    msg = @account.messages.new(content: "@advisor1 and @advisor2 please help")
    assert_equal [ "advisor1", "advisor2" ], msg.mentions
  end

  test "mentions returns empty array for no mentions" do
    msg = @account.messages.new(content: "Hello everyone")
    assert_equal [], msg.mentions
  end

  test "mentions returns empty array for nil content" do
    msg = @account.messages.new(content: nil)
    assert_equal [], msg.mentions
  end

  test "mentions returns empty array for empty content" do
    msg = @account.messages.new(content: "")
    assert_equal [], msg.mentions
  end

  test "mentions handles mentions with dashes" do
    msg = @account.messages.new(content: "@advisor-name help")
    assert_equal [ "advisor-name" ], msg.mentions
  end

  test "mentions handles mentions with underscores" do
    msg = @account.messages.new(content: "@advisor_name help")
    assert_equal [], msg.mentions
  end

  test "mentions handles mentions with numbers" do
    msg = @account.messages.new(content: "@advisor123 help")
    assert_equal [ "advisor123" ], msg.mentions
  end

  test "mentions is case-insensitive" do
    msg = @account.messages.new(content: "@Advisor @ADVISOR @advisor")
    assert_equal [ "Advisor", "ADVISOR", "advisor" ], msg.mentions
  end

  test "mentions_all? returns true for @all" do
    msg = @account.messages.new(content: "@all what do you think?")
    assert msg.mentions_all?
  end

  test "mentions_all? returns true for @everyone" do
    msg = @account.messages.new(content: "@everyone please respond")
    assert msg.mentions_all?
  end

  test "mentions_all? is case-insensitive" do
    msg = @account.messages.new(content: "@ALL @Everyone @EVERYONE")
    assert msg.mentions_all?
  end

  test "mentions_all? returns false without @all or @everyone" do
    msg = @account.messages.new(content: "@advisor help")
    assert_not msg.mentions_all?
  end

  test "mentions_all? returns false for nil content" do
    msg = @account.messages.new(content: nil)
    assert_not msg.mentions_all?
  end

  test "mentions_all? returns false for empty content" do
    msg = @account.messages.new(content: "")
    assert_not msg.mentions_all?
  end

  # ============================================================================
  # ASSOCIATIONS
  # ============================================================================

  test "belongs to conversation" do
    msg = @account.messages.new
    assert_respond_to msg, :conversation
  end

  test "belongs to sender polymorphically" do
    msg = @account.messages.new
    assert_respond_to msg, :sender
    assert_respond_to msg, :sender_type
    assert_respond_to msg, :sender_id
  end

  test "sender can be User" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert_equal @user, msg.sender
    assert_equal "User", msg.sender_type
  end

  test "sender can be Advisor" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Test"
    )
    assert_equal @advisor, msg.sender
    assert_equal "Advisor", msg.sender_type
  end

  test "has one usage_record" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert_respond_to msg, :usage_record
  end

  test "usage_record is dependent destroy" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    msg.create_usage_record!(
      account: @account,
      provider: "openai",
      model: "gpt-4",
      input_tokens: 10,
      output_tokens: 20,
      cost_cents: 5
    )

    assert_difference("UsageRecord.count", -1) do
      msg.destroy
    end
  end

  test "belongs to parent_message" do
    msg = @account.messages.new
    assert_respond_to msg, :parent_message
  end

  test "has many replies" do
    msg = @account.messages.new
    assert_respond_to msg, :replies
  end
end
