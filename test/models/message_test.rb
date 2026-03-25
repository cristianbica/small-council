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

  test "can set status to responding" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      status: "responding"
    )
    assert message.responding?
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

  test "valid status values include responding" do
    assert_equal({ "pending" => "pending", "responding" => "responding", "complete" => "complete", "error" => "error", "cancelled" => "cancelled" }, Message.statuses)
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
    assert_not_includes msg.pending_advisor_ids, advisor.id
    assert_not_includes msg.pending_advisor_ids, advisor.id.to_s
  end

  # Mention Parsing Tests
  test "extract_mentions extracts @mentions from content" do
    assert_equal [ "advisor1", "advisor-2" ], Message.extract_mentions("@advisor1 and @advisor-2 please help")
  end

  test "extract_mentions does not parse underscore handles" do
    assert_equal [ "advisor-name" ], Message.extract_mentions("@advisor_name and @advisor-name")
  end

  test "extract_mentions does not partially parse invalid handle tokens" do
    assert_equal [ "data-science" ], Message.extract_mentions("@data_science and @data-science")
  end

  test "extract_mentions returns empty array for content without mentions" do
    assert_equal [], Message.extract_mentions("Hello everyone")
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

  # Message Type Enum Tests
  test "message_type defaults to chat" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert_equal "chat", message.message_type
    assert message.chat?
  end

  test "can set message_type to compaction" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "system",
      content: "Compacted summary",
      message_type: "compaction"
    )
    assert message.compaction?
  end

  test "can set message_type to info" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "system",
      content: "user added advisor",
      message_type: "info"
    )

    assert message.info?
  end

  test "can set message_type to memory_attachment" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Attached memory",
      message_type: "memory_attachment"
    )

    assert message.memory_attachment?
  end

  test "visible_in_context excludes info but includes memory_attachment" do
    info_message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "system",
      content: "user added advisor",
      message_type: "info"
    )

    attachment_message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Attached memory",
      message_type: "memory_attachment"
    )

    visible = @conversation.messages.visible_in_context
    assert_not_includes visible, info_message
    assert_includes visible, attachment_message
  end

  test "since_last_compaction returns all messages when no compaction exists" do
    msg1 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "First message"
    )
    msg2 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Second message"
    )

    result = @conversation.messages.since_last_compaction.to_a
    assert_includes result, msg1
    assert_includes result, msg2
  end

  test "since_last_compaction returns messages from compaction onward" do
    msg1 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Before compaction"
    )
    compaction_msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "system",
      content: "Compacted state",
      message_type: "compaction",
      status: "complete"
    )
    msg2 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "After compaction"
    )

    result = @conversation.messages.since_last_compaction
    assert_not_includes result, msg1
    assert_includes result, compaction_msg
    assert_includes result, msg2
  end

  test "since_last_compaction only considers compactions from same conversation" do
    other_conversation = @account.conversations.create!(
      council: @council,
      user: @user,
      title: "Other Conversation",
      space: @space
    )

    # Create compaction in other conversation
    other_compaction = @account.messages.create!(
      conversation: other_conversation,
      sender: @user,
      role: "system",
      content: "Other conversation compaction",
      message_type: "compaction",
      status: "complete"
    )

    # Create messages in this conversation
    msg1 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "First message in this conversation"
    )
    msg2 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Second message in this conversation"
    )

    # Query from this conversation's perspective
    result = @conversation.messages.since_last_compaction
    # Should return all messages since there's no compaction in THIS conversation
    assert_includes result, msg1
    assert_includes result, msg2
    assert_not_includes result, other_compaction
  end

  test "since_last_compaction uses most recent compaction" do
    msg1 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Before first compaction"
    )
    compaction1 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "system",
      content: "First compaction",
      message_type: "compaction",
      status: "complete"
    )
    msg2 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Between compactions"
    )
    compaction2 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "system",
      content: "Second compaction",
      message_type: "compaction",
      status: "complete"
    )
    msg3 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "After second compaction"
    )

    result = @conversation.messages.since_last_compaction
    assert_not_includes result, msg1
    assert_not_includes result, compaction1
    assert_not_includes result, msg2
    assert_includes result, compaction2
    assert_includes result, msg3
  end

  test "since_last_compaction with multiple conversations each with compactions isolates correctly" do
    # Create a second conversation in the same space
    conversation2 = @account.conversations.create!(
      council: @council,
      user: @user,
      title: "Second Conversation",
      space: @space
    )

    # First conversation: msg -> compaction -> msg
    conv1_msg1 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Conv1 before compaction"
    )
    conv1_compaction = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "system",
      content: "Conv1 compaction",
      message_type: "compaction",
      status: "complete"
    )
    conv1_msg2 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Conv1 after compaction"
    )

    # Second conversation: msg -> compaction -> msg
    conv2_msg1 = @account.messages.create!(
      conversation: conversation2,
      sender: @user,
      role: "user",
      content: "Conv2 before compaction"
    )
    conv2_compaction = @account.messages.create!(
      conversation: conversation2,
      sender: @user,
      role: "system",
      content: "Conv2 compaction",
      message_type: "compaction",
      status: "complete"
    )
    conv2_msg2 = @account.messages.create!(
      conversation: conversation2,
      sender: @user,
      role: "user",
      content: "Conv2 after compaction"
    )

    # Verify conversation 1 only sees its own compaction boundary
    conv1_result = @conversation.messages.since_last_compaction
    assert_not_includes conv1_result, conv1_msg1
    assert_includes conv1_result, conv1_compaction
    assert_includes conv1_result, conv1_msg2
    # Should NOT include conversation 2's messages
    assert_not_includes conv1_result, conv2_msg1
    assert_not_includes conv1_result, conv2_compaction
    assert_not_includes conv1_result, conv2_msg2

    # Verify conversation 2 only sees its own compaction boundary
    conv2_result = conversation2.messages.since_last_compaction
    assert_not_includes conv2_result, conv2_msg1
    assert_includes conv2_result, conv2_compaction
    assert_includes conv2_result, conv2_msg2
    # Should NOT include conversation 1's messages
    assert_not_includes conv2_result, conv1_msg1
    assert_not_includes conv2_result, conv1_compaction
    assert_not_includes conv2_result, conv1_msg2
  end

  # Previous message tests
  test "previous_message returns message immediately before current" do
    msg1 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "First message"
    )
    msg2 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Second message"
    )
    msg3 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Third message"
    )

    assert_equal msg2, msg3.previous_message
    assert_equal msg1, msg2.previous_message
    assert_nil msg1.previous_message
  end

  test "previous_message returns nil for first message in conversation" do
    msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Only message"
    )

    assert_nil msg.previous_message
  end

  test "previous_message works with compaction messages" do
    msg1 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Before compaction"
    )
    compaction = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "system",
      content: "Compaction summary",
      message_type: "compaction",
      status: "complete"
    )
    msg2 = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "After compaction"
    )

    assert_equal compaction, msg2.previous_message
    assert_equal msg1, compaction.previous_message
  end

  # Retry functionality tests
  test "retry! returns false for non-error messages" do
    complete_msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Complete message",
      status: "complete"
    )

    assert_not complete_msg.retry!
  end

  test "retry! returns false for non-advisor messages" do
    error_msg = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Error message",
      status: "error"
    )

    assert_not error_msg.retry!
  end

  test "retry! updates status and triggers AI call for errored advisor messages" do
    advisor = @account.advisors.first
    parent = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Parent message",
      pending_advisor_ids: []
    )

    error_msg = @account.messages.create!(
      conversation: @conversation,
      sender: advisor,
      role: "advisor",
      parent_message: parent,
      content: "Error: API failed",
      status: "error",
      debug_data: { error_at: "2024-01-01" }
    )

    # Mock the AI call
    AI.expects(:generate_advisor_response).with(
      advisor: advisor,
      message: error_msg,
      async: true
    )

    assert error_msg.retry!

    # Verify status updated
    assert_equal "responding", error_msg.reload.status
    assert_equal "...", error_msg.content
  end

  test "retry! re-adds to parent pending list" do
    advisor = @account.advisors.first
    parent = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Parent message",
      pending_advisor_ids: []
    )

    error_msg = @account.messages.create!(
      conversation: @conversation,
      sender: advisor,
      role: "advisor",
      parent_message: parent,
      content: "Error: API failed",
      status: "error"
    )

    AI.stubs(:generate_advisor_response)

    error_msg.retry!

    # Verify parent has advisor in pending again
    assert_includes parent.reload.pending_advisor_ids, advisor.id.to_s
  end

  # Missing coverage tests
  test "extract_mentions finds all @mentions in text" do
    text = "Hello @advisor1 and @advisor-two, please help @advisor-three"
    mentions = Message.extract_mentions(text)
    assert_equal [ "advisor1", "advisor-two", "advisor-three" ], mentions
  end

  test "extract_mentions returns empty array for blank text" do
    assert_empty Message.extract_mentions(nil)
    assert_empty Message.extract_mentions("")
    assert_empty Message.extract_mentions("   ")
  end

  test "extract_mentions ignores invalid mention formats" do
    text = "@valid but not @-invalid or @ or @"
    mentions = Message.extract_mentions(text)
    assert_equal [ "valid" ], mentions
  end

  test "from_scribe? returns true when sender is scribe advisor" do
    scribe = @account.advisors.create!(
      name: "test-scribe-#{SecureRandom.hex(4)}",
      space: @space,
      system_prompt: "You are scribe",
      is_scribe: true
    )
    message = @account.messages.create!(
      conversation: @conversation,
      sender: scribe,
      role: "advisor",
      content: "Scribe message"
    )
    assert message.from_scribe?
  end

  test "from_scribe? returns false when sender is regular advisor" do
    regular_advisor = @account.advisors.create!(
      name: "test-regular-#{SecureRandom.hex(4)}",
      space: @space,
      system_prompt: "You are advisor"
    )
    message = @account.messages.create!(
      conversation: @conversation,
      sender: regular_advisor,
      role: "advisor",
      content: "Regular message"
    )
    assert_not message.from_scribe?
  end

  test "from_scribe? returns false when sender is user" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "User message"
    )
    assert_not message.from_scribe?
  end

  test "from_non_scribe_advisor? returns true for regular advisor" do
    regular_advisor = @account.advisors.create!(
      name: "test-regular-#{SecureRandom.hex(4)}",
      space: @space,
      system_prompt: "You are advisor"
    )
    message = @account.messages.create!(
      conversation: @conversation,
      sender: regular_advisor,
      role: "advisor",
      content: "Regular message"
    )
    assert message.from_non_scribe_advisor?
  end

  test "from_non_scribe_advisor? returns false for scribe" do
    scribe = @account.advisors.create!(
      name: "test-scribe-#{SecureRandom.hex(4)}",
      space: @space,
      system_prompt: "You are scribe",
      is_scribe: true
    )
    message = @account.messages.create!(
      conversation: @conversation,
      sender: scribe,
      role: "advisor",
      content: "Scribe message"
    )
    assert_not message.from_non_scribe_advisor?
  end

  test "from_user? returns true when sender is user" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "User message"
    )
    assert message.from_user?
  end

  test "from_user? returns false when sender is advisor" do
    advisor = @account.advisors.create!(
      name: "test-advisor-#{SecureRandom.hex(4)}",
      space: @space,
      system_prompt: "You are advisor"
    )
    message = @account.messages.create!(
      conversation: @conversation,
      sender: advisor,
      role: "advisor",
      content: "Advisor message"
    )
    assert_not message.from_user?
  end

  test "retry_count returns integer from debug_data" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      debug_data: { "retry_count" => 3 }
    )
    assert_equal 3, message.retry_count
  end

  test "retry_count returns 0 when not set" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    assert_equal 0, message.retry_count
  end

  test "add_to_parent_message adds sender to pending list" do
    parent = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Parent message",
      pending_advisor_ids: []
    )
    advisor = @account.advisors.create!(
      name: "test-advisor-#{SecureRandom.hex(4)}",
      space: @space,
      system_prompt: "You are advisor"
    )
    child = @account.messages.create!(
      conversation: @conversation,
      sender: advisor,
      role: "advisor",
      parent_message: parent,
      content: "Child message"
    )

    child.add_to_parent_message

    assert_includes parent.reload.pending_advisor_ids, advisor.id.to_s
  end

  test "add_to_parent_message does not duplicate pending advisor" do
    parent = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Parent message",
      pending_advisor_ids: []
    )
    advisor = @account.advisors.create!(
      name: "test-advisor-#{SecureRandom.hex(4)}",
      space: @space,
      system_prompt: "You are advisor"
    )
    child = @account.messages.create!(
      conversation: @conversation,
      sender: advisor,
      role: "advisor",
      parent_message: parent,
      content: "Child message"
    )

    child.add_to_parent_message
    child.add_to_parent_message  # Call twice

    assert_equal 1, parent.reload.pending_advisor_ids.count(advisor.id.to_s)
  end

  test "visible_in_chat? returns false for pending messages" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Pending",
      status: "pending"
    )
    assert_not message.send(:visible_in_chat?)
  end

  test "visible_in_chat? returns true for complete messages" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Complete",
      status: "complete"
    )
    assert message.send(:visible_in_chat?)
  end

  test "broadcastable_create? returns true for visible messages" do
    message = @account.messages.new(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    message.status = "complete"
    assert message.send(:broadcastable_create?)
  end

  test "broadcastable_create? returns false for pending messages" do
    message = @account.messages.new(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test"
    )
    message.status = "pending"
    assert_not message.send(:broadcastable_create?)
  end

  test "broadcastable_update? returns true when status changes to visible" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Test",
      status: "pending"
    )
    message.status = "complete"
    assert message.send(:broadcastable_update?)
  end

  test "broadcastable_update? returns true when content changes" do
    message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Original",
      status: "complete"
    )
    message.content = "Updated"
    assert message.send(:broadcastable_update?)
  end
end
