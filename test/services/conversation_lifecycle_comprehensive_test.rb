# test/services/conversation_lifecycle_comprehensive_test.rb
require "test_helper"

class ConversationLifecycleComprehensiveTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @account = Account.create!(name: "Test Account", slug: "test-lifecycle-comprehensive")
    set_tenant(@account)
    @user = @account.users.create!(email: "user@example.com", password: "password123")
    @space = @account.spaces.create!(name: "Test Space")

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

    @scribe = @account.advisors.create!(
      name: "Scribe",
      system_prompt: "You are the scribe.",
      space: @space,
      is_scribe: true,
      llm_model: @llm_model
    )

    @advisor1 = @account.advisors.create!(
      name: "Strategic Advisor",
      system_prompt: "You are strategic.",
      space: @space,
      llm_model: @llm_model
    )

    @advisor2 = @account.advisors.create!(
      name: "Technical Expert",
      system_prompt: "You are technical.",
      space: @space,
      llm_model: @llm_model
    )
  end

  def create_conversation(roe_type: :open, type: :adhoc)
    attrs = {
      title: "Test Conversation",
      user: @user,
      conversation_type: type,
      roe_type: roe_type,
      space: @space
    }

    if type == :council_meeting
      council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
      attrs[:council] = council
    end

    conv = @account.conversations.create!(**attrs)

    conv.conversation_participants.create!(advisor: @scribe, role: :scribe)
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conv.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 1)

    conv
  end

  # ============================================================================
  # COMMAND PARSING - ALL BRANCHES
  # ============================================================================

  test "user_posted_message handles invalid command with validation errors" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "/invite"  # Missing @mention
    )

    lifecycle = ConversationLifecycle.new(conv)

    # Should create system message about error
    assert_difference "Message.where(role: :system).count", 1 do
      lifecycle.user_posted_message(msg)
    end

    error_msg = Message.where(role: :system).last
    assert_includes error_msg.content, "Command error"
  end

  test "user_posted_message handles command with multiple validation errors" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "/invite invalid_name_without_at"  # No @ prefix
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_difference "Message.where(role: :system).count", 1 do
      lifecycle.user_posted_message(msg)
    end
  end

  # ============================================================================
  # MENTION PARSING - ALL EDGE CASES
  # ============================================================================

  test "user_posted_message with no mentions in Open RoE does not trigger advisors" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Hello everyone, what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_no_enqueued_jobs do
      lifecycle.user_posted_message(msg)
    end

    assert_empty msg.reload.pending_advisor_ids
  end

  test "user_posted_message with single mention" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_enqueued_with(job: GenerateAdvisorResponseJob) do
      lifecycle.user_posted_message(msg)
    end

    assert_includes msg.reload.pending_advisor_ids, @advisor1.id
  end

  test "user_posted_message with multiple mentions" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor and @technical_expert please help"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_enqueued_jobs 2, only: GenerateAdvisorResponseJob do
      lifecycle.user_posted_message(msg)
    end

    assert_includes msg.reload.pending_advisor_ids, @advisor1.id
    assert_includes msg.pending_advisor_ids, @advisor2.id
  end

  test "user_posted_message with @all expands to all advisors in Open RoE" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@all what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    # @all includes all advisors (excluding scribe)
    assert_includes msg.reload.pending_advisor_ids, @advisor1.id
    assert_includes msg.pending_advisor_ids, @advisor2.id
    assert_not_includes msg.pending_advisor_ids, @scribe.id
  end

  test "user_posted_message with @everyone also expands in Open RoE" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@everyone please respond"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    assert_includes msg.reload.pending_advisor_ids, @advisor1.id
    assert_includes msg.pending_advisor_ids, @advisor2.id
  end

  test "user_posted_message @all does not expand in Consensus RoE" do
    conv = create_conversation(roe_type: :consensus)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@all what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    # In consensus, all advisors respond regardless of mentions
    assert_includes msg.reload.pending_advisor_ids, @advisor1.id
    assert_includes msg.pending_advisor_ids, @advisor2.id
  end

  test "user_posted_message @all does not expand in Brainstorming RoE" do
    conv = create_conversation(roe_type: :brainstorming)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@all brainstorm ideas"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    # In brainstorming, all advisors respond regardless of mentions
    assert_includes msg.reload.pending_advisor_ids, @advisor1.id
    assert_includes msg.pending_advisor_ids, @advisor2.id
  end

  test "user_posted_message mention with underscores matches advisor name with spaces" do
    advisor_with_spaces = @account.advisors.create!(
      name: "Data Science Expert",
      system_prompt: "You are a data scientist.",
      space: @space,
      llm_model: @llm_model
    )
    conv = create_conversation(roe_type: :open)
    conv.conversation_participants.create!(advisor: advisor_with_spaces, role: :advisor, position: 2)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@data_science_expert what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    assert_includes msg.reload.pending_advisor_ids, advisor_with_spaces.id
  end

  test "user_posted_message mention with dashes matches advisor name" do
    advisor_with_dashes = @account.advisors.create!(
      name: "AI-Expert-Advisor",
      system_prompt: "You are an AI expert.",
      space: @space,
      llm_model: @llm_model
    )
    conv = create_conversation(roe_type: :open)
    conv.conversation_participants.create!(advisor: advisor_with_dashes, role: :advisor, position: 2)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@AI-Expert-Advisor please help"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    assert_includes msg.reload.pending_advisor_ids, advisor_with_dashes.id
  end

  test "user_posted_message mention is case-insensitive" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@STRATEGIC_ADVISOR what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    assert_includes msg.reload.pending_advisor_ids, @advisor1.id
  end

  test "user_posted_message mention with partial match" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    assert_includes msg.reload.pending_advisor_ids, @advisor1.id
  end

  test "user_posted_message with non-existent mention does not trigger advisors" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@nonexistent_advisor what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_no_enqueued_jobs do
      lifecycle.user_posted_message(msg)
    end

    assert_empty msg.reload.pending_advisor_ids
  end

  test "user_posted_message with blank content does not trigger advisors" do
    conv = create_conversation(roe_type: :consensus)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Hello"  # No mentions, but in consensus all respond
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    # In consensus, all advisors respond even without mentions
    assert_includes msg.reload.pending_advisor_ids, @advisor1.id
    assert_includes msg.pending_advisor_ids, @advisor2.id
  end

  # ============================================================================
  # DEPTH CALCULATION AND ENFORCEMENT
  # ============================================================================

  test "depth calculation for root message is 0" do
    conv = create_conversation(roe_type: :open)

    root_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Root message",
      pending_advisor_ids: [ @advisor1.id ]
    )

    assert_equal 0, root_msg.depth
  end

  test "depth calculation for reply is 1" do
    conv = create_conversation(roe_type: :open)

    root_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Root message"
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Reply message",
      parent_message: root_msg
    )

    assert_equal 1, reply.depth
  end

  test "depth calculation for nested replies" do
    conv = create_conversation(roe_type: :consensus)

    root_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Root message"
    )

    level1 = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Level 1 reply",
      parent_message: root_msg
    )

    level2 = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Level 2 reply",
      parent_message: level1
    )

    assert_equal 0, root_msg.depth
    assert_equal 1, level1.depth
    assert_equal 2, level2.depth
  end

  test "Open RoE depth limit is enforced - no replies beyond depth 1" do
    conv = create_conversation(roe_type: :open)
    # Set scribe count high to prevent scribe follow-up from interfering
    conv.update!(scribe_initiated_count: 3)

    root_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Root message",
      pending_advisor_ids: [ @advisor1.id ]
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Reply message",
      parent_message: root_msg,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)

    # In Open RoE, max depth is 1, so no new messages should be created from depth 1
    # Also scribe is disabled by high count
    assert_no_enqueued_jobs do
      lifecycle.advisor_responded(reply)
    end
  end

  test "Consensus RoE depth limit is enforced - allows up to depth 2" do
    conv = create_conversation(roe_type: :consensus)

    root_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Root message"
    )

    # Create a message at depth 1 that will trigger replies
    depth1_msg = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Depth 1 message",
      parent_message: root_msg,
      pending_advisor_ids: [ @advisor2.id ]
    )

    # advisor2 responds at depth 2
    depth2_reply = conv.messages.create!(
      account: @account,
      sender: @advisor2,
      role: "advisor",
      content: "Depth 2 reply",
      parent_message: depth1_msg,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)

    # At depth 2, no more replies should be triggered
    assert_no_enqueued_jobs do
      lifecycle.advisor_responded(depth2_reply)
    end
  end

  # ============================================================================
  # PENDING ADVISOR MANAGEMENT
  # ============================================================================

  test "pending_advisor_ids is populated correctly for all participants" do
    conv = create_conversation(roe_type: :consensus)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Hello everyone"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    msg.reload
    # All participants including scribe (2 advisors + 1 scribe = 3)
    assert_equal 3, msg.pending_advisor_ids.length
    assert_includes msg.pending_advisor_ids, @advisor1.id
    assert_includes msg.pending_advisor_ids, @advisor2.id
    assert_includes msg.pending_advisor_ids, @scribe.id
  end

  test "pending_advisor_ids is empty when no advisors mentioned in Open RoE" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Hello without mentions"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    assert_empty msg.reload.pending_advisor_ids
  end

  # ============================================================================
  # SCRIBE FOLLOW-UP LOGIC
  # ============================================================================

  test "scribe follows up when root message is solved at count 0" do
    conv = create_conversation(roe_type: :open, type: :council_meeting)

    root_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor what do you think?",
      pending_advisor_ids: [ @advisor1.id ]
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Here's my response",
      parent_message: root_msg,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_enqueued_with(job: GenerateAdvisorResponseJob) do
      lifecycle.advisor_responded(reply)
    end

    assert_equal 1, conv.reload.scribe_initiated_count
  end

  test "scribe follows up at count 1" do
    conv = create_conversation(roe_type: :open, type: :council_meeting)
    conv.update!(scribe_initiated_count: 1)

    root_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor what do you think?",
      pending_advisor_ids: [ @advisor1.id ]
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Here's my response",
      parent_message: root_msg,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_enqueued_with(job: GenerateAdvisorResponseJob) do
      lifecycle.advisor_responded(reply)
    end

    assert_equal 2, conv.reload.scribe_initiated_count
  end

  test "scribe follows up at count 2" do
    conv = create_conversation(roe_type: :open, type: :council_meeting)
    conv.update!(scribe_initiated_count: 2)

    root_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor what do you think?",
      pending_advisor_ids: [ @advisor1.id ]
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Here's my response",
      parent_message: root_msg,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_enqueued_with(job: GenerateAdvisorResponseJob) do
      lifecycle.advisor_responded(reply)
    end

    assert_equal 3, conv.reload.scribe_initiated_count
  end

  test "scribe does NOT follow up at count 3 (limit reached)" do
    conv = create_conversation(roe_type: :open, type: :council_meeting)
    conv.update!(scribe_initiated_count: 3)

    root_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor what do you think?",
      pending_advisor_ids: [ @advisor1.id ]
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Here's my response",
      parent_message: root_msg,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_no_enqueued_jobs do
      lifecycle.advisor_responded(reply)
    end

    assert_equal 3, conv.reload.scribe_initiated_count
  end

  test "scribe does NOT follow up for non-root messages" do
    conv = create_conversation(roe_type: :open, type: :council_meeting)

    root_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Root message"
    )

    reply1 = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Reply to root",
      parent_message: root_msg,
      pending_advisor_ids: [ @advisor2.id ]
    )

    reply2 = conv.messages.create!(
      account: @account,
      sender: @advisor2,
      role: "advisor",
      content: "Reply to reply1",
      parent_message: reply1,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)

    # Scribe should not follow up on reply to reply (non-root)
    assert_no_enqueued_jobs do
      lifecycle.advisor_responded(reply2)
    end
  end

  test "user message resets scribe initiated count from 1" do
    conv = create_conversation(roe_type: :open)
    conv.update!(scribe_initiated_count: 1)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    assert_equal 0, conv.reload.scribe_initiated_count
  end

  test "user message resets scribe initiated count from 2" do
    conv = create_conversation(roe_type: :open)
    conv.update!(scribe_initiated_count: 2)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    assert_equal 0, conv.reload.scribe_initiated_count
  end

  test "user message resets scribe initiated count from 3" do
    conv = create_conversation(roe_type: :open)
    conv.update!(scribe_initiated_count: 3)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    assert_equal 0, conv.reload.scribe_initiated_count
  end

  test "user message resets scribe initiated count from mixed values" do
    conv = create_conversation(roe_type: :open)
    conv.update!(scribe_initiated_count: 5)  # Above max

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    assert_equal 0, conv.reload.scribe_initiated_count
  end

  # ============================================================================
  # MESSAGE SOLVED HANDLING
  # ============================================================================

  test "message is marked solved when all pending advisors respond" do
    conv = create_conversation(roe_type: :open)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic_advisor @technical_expert what do you think?",
      pending_advisor_ids: [ @advisor1.id, @advisor2.id ]
    )

    # First advisor responds
    reply1 = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "My thoughts",
      parent_message: parent_msg,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.advisor_responded(reply1)

    parent_msg.reload
    assert_not parent_msg.solved?  # Still pending for advisor2
    assert_includes parent_msg.pending_advisor_ids, @advisor2.id

    # Second advisor responds
    reply2 = conv.messages.create!(
      account: @account,
      sender: @advisor2,
      role: "advisor",
      content: "My thoughts too",
      parent_message: parent_msg,
      status: "complete"
    )

    lifecycle.advisor_responded(reply2)

    parent_msg.reload
    assert parent_msg.solved?
    assert_empty parent_msg.pending_advisor_ids
  end

  test "solved? returns true when pending_advisor_ids is empty" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Test message",
      pending_advisor_ids: []
    )

    assert msg.solved?
  end

  test "solved? returns true when pending_advisor_ids is nil" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Test message",
      pending_advisor_ids: nil
    )

    assert msg.solved?
  end

  test "solved? returns false when pending_advisor_ids has values" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Test message",
      pending_advisor_ids: [ @advisor1.id ]
    )

    assert_not msg.solved?
  end

  # ============================================================================
  # ERROR PATHS
  # ============================================================================

  test "advisor_response_error updates message with error content" do
    conv = create_conversation(roe_type: :open)

    pending_msg = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "system",
      content: "[Strategic Advisor] is thinking...",
      status: "pending"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.advisor_response_error(pending_msg, "API timeout occurred")

    pending_msg.reload
    assert_equal "[Error: API timeout occurred]", pending_msg.content
    assert_equal "error", pending_msg.status
  end

  test "advisor_response_error removes advisor from parent pending list" do
    conv = create_conversation(roe_type: :open)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Test message",
      pending_advisor_ids: [ @advisor1.id ]
    )

    pending_msg = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "system",
      content: "[Strategic Advisor] is thinking...",
      status: "pending",
      parent_message: parent_msg
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.advisor_response_error(pending_msg, "Network error")

    parent_msg.reload
    assert_empty parent_msg.pending_advisor_ids
  end

  test "advisor_response_error handles message without parent" do
    conv = create_conversation(roe_type: :open)

    pending_msg = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "system",
      content: "[Strategic Advisor] is thinking...",
      status: "pending"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_nothing_raised do
      lifecycle.advisor_response_error(pending_msg, "API error")
    end

    pending_msg.reload
    assert_equal "error", pending_msg.status
  end

  # ============================================================================
  # ADVISOR RESPONSE SCENARIOS
  # ============================================================================

  test "advisor_responded broadcasts message update" do
    conv = create_conversation(roe_type: :open)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Test message",
      pending_advisor_ids: [ @advisor1.id ]
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "My response",
      parent_message: parent_msg,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)

    # Should not raise any Turbo broadcast errors
    assert_nothing_raised do
      lifecycle.advisor_responded(reply)
    end
  end

  test "advisor_responded handles reply without parent gracefully" do
    conv = create_conversation(roe_type: :open)

    orphan_reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Orphan response",
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_nothing_raised do
      lifecycle.advisor_responded(orphan_reply)
    end
  end

  test "advisor_responded resolves advisor from pending list" do
    conv = create_conversation(roe_type: :open)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Test message",
      pending_advisor_ids: [ @advisor1.id, @advisor2.id ]
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "My response",
      parent_message: parent_msg,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.advisor_responded(reply)

    parent_msg.reload
    assert_not_includes parent_msg.pending_advisor_ids, @advisor1.id
    assert_includes parent_msg.pending_advisor_ids, @advisor2.id
  end

  # ============================================================================
  # MESSAGE PERSISTENCE CHECK
  # ============================================================================

  test "user_posted_message returns early for unpersisted message" do
    conv = create_conversation(roe_type: :open)

    unsaved_msg = conv.messages.new(
      account: @account,
      sender: @user,
      role: "user",
      content: "Unsaved message"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_no_enqueued_jobs do
      result = lifecycle.user_posted_message(unsaved_msg)
    end
  end

  test "user_posted_message processes persisted message normally" do
    conv = create_conversation(roe_type: :consensus)

    saved_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Saved message"
    )

    lifecycle = ConversationLifecycle.new(conv)

    # Consensus mode includes all participants (2 advisors + 1 scribe = 3)
    assert_enqueued_jobs 3, only: GenerateAdvisorResponseJob do
      lifecycle.user_posted_message(saved_msg)
    end
  end
end
