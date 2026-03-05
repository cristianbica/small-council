# test/services/conversation_lifecycle_test.rb
require "test_helper"

class ConversationLifecycleTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @account = Account.create!(name: "Test Account", slug: "test-lifecycle-account")
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

    # Add scribe
    conv.conversation_participants.create!(advisor: @scribe, role: :scribe)

    # Add advisors
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conv.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 1)

    conv
  end

  # Basic Flow Tests
  test "user_posted_message creates pending messages and enqueues jobs for mentioned advisors" do
    conv = create_conversation(roe_type: :consensus)

    user_message = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Hello everyone"
    )

    lifecycle = ConversationLifecycle.new(conv)

    # In consensus mode, all participants get pending placeholders (2 advisors + 1 scribe = 3)
    # and each placeholder is enqueued immediately.
    assert_difference "Message.where(status: :pending).count", 3 do
      assert_enqueued_jobs 1, only: GenerateAdvisorResponseJob do
        lifecycle.user_posted_message(user_message)
      end
    end
  end

  test "open mentions enqueue all mentioned advisors immediately" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic-advisor @technical-expert share your thoughts"
    )

    lifecycle = ConversationLifecycle.new(conv)

    clear_enqueued_jobs
    lifecycle.user_posted_message(msg)

    assert_equal 1, enqueued_jobs.size
  end

  test "turn-based flow enqueues legacy system-role pending advisor placeholders" do
    conv = create_conversation(roe_type: :open)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic-advisor @technical-expert share your thoughts",
      pending_advisor_ids: [ @advisor1.id, @advisor2.id ]
    )

    completed = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      status: "complete",
      content: "First advisor response",
      parent_message: parent_msg
    )

    conv.messages.create!(
      account: @account,
      sender: @advisor2,
      role: "system",
      status: "pending",
      content: "[Technical Expert] is thinking...",
      parent_message: parent_msg
    )

    lifecycle = ConversationLifecycle.new(conv)
    clear_enqueued_jobs

    lifecycle.advisor_responded(completed)

    assert_equal 1, enqueued_jobs.size
    payload = enqueued_jobs.last[:args][0]
    advisor_id = payload[:advisor_id] || payload["advisor_id"]
    assert_equal @advisor2.id, advisor_id
  end

  test "user_posted_message returns early if message not persisted" do
    conv = create_conversation

    user_message = conv.messages.new(
      sender: @user,
      role: "user",
      content: "Hello"
    )
    # Don't save - so persisted? returns false

    lifecycle = ConversationLifecycle.new(conv)

    assert_no_difference "Message.where(status: :pending).count" do
      lifecycle.user_posted_message(user_message)
    end
  end

  test "advisor_responded updates message and removes from pending" do
    conv = create_conversation(roe_type: :open)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic-advisor what do you think?",
      pending_advisor_ids: [ @advisor1.id ]
    )

    pending_message = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "[Strategic Advisor] is thinking...",
      status: "pending",
      parent_message: parent_msg
    )

    # Mark the pending as complete
    pending_message.update!(content: "Here's my response", role: "advisor", status: "complete")

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.advisor_responded(pending_message)

    parent_msg.reload
    assert parent_msg.solved?
    assert_empty parent_msg.pending_advisor_ids
  end

  test "advisor_responded returns early if no parent message" do
    conv = create_conversation

    # Create an orphan message with no parent
    message = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Orphan response",
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)

    # Should not raise error
    assert_nothing_raised do
      lifecycle.advisor_responded(message)
    end
  end

  # Command Handling Tests
  test "user_posted_message processes invite command" do
    conv = create_conversation
    advisor3 = @account.advisors.create!(
      name: "New Advisor",
      system_prompt: "You are new.",
      space: @space,
      llm_model: @llm_model
    )

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "/invite @new-advisor"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    # Reload to get updated advisors
    conv.reload
    assert_includes conv.advisors, advisor3, "Expected advisor3 to be in conversation advisors"
  end

  # Open RoE Tests
  test "Open RoE: mentioned advisors respond" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic-advisor what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_enqueued_with(job: GenerateAdvisorResponseJob) do
      lifecycle.user_posted_message(msg)
    end

    assert_includes msg.pending_advisor_ids, @advisor1.id
    assert_not_includes msg.pending_advisor_ids, @advisor2.id
  end

  test "Open RoE: no advisors respond without mention" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "What does everyone think?"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_no_enqueued_jobs do
      lifecycle.user_posted_message(msg)
    end

    assert_empty msg.pending_advisor_ids
  end

  test "Open RoE: @all expands to all advisors excluding scribe" do
    conv = create_conversation(roe_type: :open)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@all what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    # @all includes all advisors: 2 advisors
    assert_includes msg.pending_advisor_ids, @advisor1.id
    assert_includes msg.pending_advisor_ids, @advisor2.id
    assert_not_includes msg.pending_advisor_ids, @scribe.id
  end

  # Consensus RoE Tests
  test "Consensus RoE: all participants respond including scribe" do
    conv = create_conversation(roe_type: :consensus)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "What do you all think?"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    # All participants including scribe respond in consensus mode
    assert_includes msg.pending_advisor_ids, @advisor1.id
    assert_includes msg.pending_advisor_ids, @advisor2.id
    assert_includes msg.pending_advisor_ids, @scribe.id
  end

  # Depth Limit Tests
  test "Open RoE: max depth is 1" do
    conv = create_conversation(roe_type: :open)
    assert_equal 1, conv.max_depth
  end

  test "Consensus RoE: max depth is 5" do
    conv = create_conversation(roe_type: :consensus)
    assert_equal 5, conv.max_depth
  end

  test "Brainstorming RoE: max depth is 2" do
    conv = create_conversation(roe_type: :brainstorming)
    assert_equal 2, conv.max_depth
  end

  # Message Solved Tests
  test "advisor_responded marks message as solved when all pending cleared" do
    conv = create_conversation(roe_type: :open)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic-advisor what do you think?",
      pending_advisor_ids: [ @advisor1.id ]
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Here's my response",
      parent_message: parent_msg
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.advisor_responded(reply)

    parent_msg.reload
    assert parent_msg.solved?
  end

  # Scribe Follow-up Tests
  test "scribe follows up when root message is solved in council meeting" do
    conv = create_conversation(roe_type: :open, type: :council_meeting)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic-advisor what do you think?",
      pending_advisor_ids: [ @advisor1.id ]
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Here's my response",
      parent_message: parent_msg
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_enqueued_with(job: GenerateAdvisorResponseJob) do
      lifecycle.advisor_responded(reply)
    end

    assert_equal 1, conv.reload.scribe_initiated_count
  end

  test "scribe stops after 3 consecutive follow-ups" do
    conv = create_conversation(roe_type: :open, type: :council_meeting)
    conv.update!(scribe_initiated_count: 3)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic-advisor what do you think?",
      pending_advisor_ids: [ @advisor1.id ]
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Here's my response",
      parent_message: parent_msg
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_no_enqueued_jobs do
      lifecycle.advisor_responded(reply)
    end
  end

  test "user message resets scribe initiated count" do
    conv = create_conversation(roe_type: :open)
    conv.update!(scribe_initiated_count: 2)

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic-advisor what do you think?"
    )

    lifecycle = ConversationLifecycle.new(conv)
    lifecycle.user_posted_message(msg)

    assert_equal 0, conv.reload.scribe_initiated_count
  end

  test "handles command validation errors" do
    conv = create_conversation

    msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "/invite"  # Missing @mention
    )

    lifecycle = ConversationLifecycle.new(conv)

    # Should create a system message about the error
    assert_difference "Message.where(role: :system).count", 1 do
      lifecycle.user_posted_message(msg)
    end
  end

  # Scribe Follow-up Guard Clause Tests
  test "handle_message_solved is a no-op for adhoc conversations" do
    conv = create_conversation(roe_type: :open, type: :adhoc)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic-advisor what do you think?",
      pending_advisor_ids: [ @advisor1.id ]
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Here's my response",
      parent_message: parent_msg
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_no_enqueued_jobs do
      lifecycle.advisor_responded(reply)
    end

    assert_equal 0, conv.reload.scribe_initiated_count
  end

  test "handle_message_solved is a no-op when conversation is resolved" do
    conv = create_conversation(roe_type: :open, type: :council_meeting)
    conv.update!(status: :resolved)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic-advisor what do you think?",
      pending_advisor_ids: [ @advisor1.id ]
    )

    reply = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "Here's my response",
      parent_message: parent_msg
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_no_enqueued_jobs do
      lifecycle.advisor_responded(reply)
    end

    assert_equal 0, conv.reload.scribe_initiated_count
  end

  test "advisor mention in advisor response triggers mentioned advisor follow-up" do
    conv = create_conversation(roe_type: :consensus)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic-advisor and @technical-expert discuss this",
      pending_advisor_ids: [ @advisor1.id ]
    )

    advisor_message = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "@technical-expert can you validate feasibility?",
      parent_message: parent_msg,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)

    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: GenerateAdvisorResponseJob do
      lifecycle.advisor_responded(advisor_message)
    end

    payload = enqueued_jobs.last[:args][0]
    advisor_id = payload[:advisor_id] || payload["advisor_id"]
    conversation_id = payload[:conversation_id] || payload["conversation_id"]
    message_id = payload[:message_id] || payload["message_id"]

    assert_equal @advisor2.id, advisor_id
    assert_equal conv.id, conversation_id
    assert message_id.is_a?(Integer)

    parent_msg.reload
    assert_includes parent_msg.pending_advisor_ids, @advisor2.id
  end

  test "advisor mention does not trigger self-response" do
    conv = create_conversation(roe_type: :consensus)

    parent_msg = conv.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "@strategic-advisor review",
      pending_advisor_ids: [ @advisor1.id ]
    )

    advisor_message = conv.messages.create!(
      account: @account,
      sender: @advisor1,
      role: "advisor",
      content: "@strategic-advisor I agree with my prior point",
      parent_message: parent_msg,
      status: "complete"
    )

    lifecycle = ConversationLifecycle.new(conv)

    assert_no_enqueued_jobs do
      lifecycle.advisor_responded(advisor_message)
    end

    parent_msg.reload
    assert_equal [], parent_msg.pending_advisor_ids
  end
end
