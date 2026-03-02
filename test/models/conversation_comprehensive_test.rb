# test/models/conversation_comprehensive_test.rb
require "test_helper"

class ConversationComprehensiveTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-conversation-comprehensive")
    set_tenant(@account)
    @user = @account.users.create!(email: "user@example.com", password: "password123")
    @space = @account.spaces.create!(name: "Test Space")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

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

  # ============================================================================
  # TYPE METHODS
  # ============================================================================

  test "conversation_type defaults to council_meeting" do
    conv = @account.conversations.new(
      title: "Test",
      user: @user,
      council: @council,
      space: @space
    )
    # Default is council_meeting but needs validation
    conv.save(validate: false)
    assert_equal "council_meeting", conv.conversation_type
  end

  test "council_meeting? returns true for council meeting type" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      conversation_type: :council_meeting,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    assert conv.council_meeting?
  end

  test "council_meeting? returns false for adhoc type" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    assert_not conv.council_meeting?
  end

  test "adhoc? returns true for adhoc type" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    assert conv.adhoc?
  end

  test "adhoc? returns false for council_meeting type" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      conversation_type: :council_meeting,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    assert_not conv.adhoc?
  end

  # ============================================================================
  # ROE TYPE METHODS
  # ============================================================================

  test "roe_type defaults to open" do
    conv = @account.conversations.new(
      title: "Test",
      user: @user,
      council: @council,
      space: @space
    )
    conv.save(validate: false)
    assert_equal "open", conv.roe_type
    assert conv.open?
  end

  test "open? returns true for open roe" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      roe_type: :open,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    assert conv.open?
  end

  test "consensus? returns true for consensus roe" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      roe_type: :consensus,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    assert conv.consensus?
  end

  test "brainstorming? returns true for brainstorming roe" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      roe_type: :brainstorming,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    assert conv.brainstorming?
  end

  test "roe_type can be changed" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      roe_type: :open,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    conv.update!(roe_type: :consensus)
    assert conv.consensus?
    assert_not conv.open?

    conv.update!(roe_type: :brainstorming)
    assert conv.brainstorming?
  end

  # ============================================================================
  # SCRIBE METHODS
  # ============================================================================

  test "scribe_participant returns scribe participant" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    scribe_participant = conv.conversation_participants.create!(advisor: @scribe, role: :scribe)

    assert_equal scribe_participant, conv.scribe_participant
  end

  test "scribe_participant returns nil when no scribe" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_nil conv.scribe_participant
  end

  test "scribe_advisor returns scribe advisor" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conv.conversation_participants.create!(advisor: @scribe, role: :scribe)

    assert_equal @scribe, conv.scribe_advisor
  end

  test "scribe_advisor returns nil when no scribe" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_nil conv.scribe_advisor
  end

  test "has_scribe? returns true when scribe present" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conv.conversation_participants.create!(advisor: @scribe, role: :scribe)

    assert conv.has_scribe?
  end

  test "has_scribe? returns false when no scribe" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_not conv.has_scribe?
  end

  test "ensure_scribe_present! adds scribe when missing" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_not conv.has_scribe?

    conv.ensure_scribe_present!

    assert conv.has_scribe?
    assert_equal @scribe, conv.scribe_advisor
  end

  test "ensure_scribe_present! does nothing when scribe already present" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conv.conversation_participants.create!(advisor: @scribe, role: :scribe)

    initial_count = conv.conversation_participants.count

    conv.ensure_scribe_present!

    assert_equal initial_count, conv.conversation_participants.count
  end

  test "ensure_scribe_present! does nothing when no scribe in account" do
    account_without_scribe = Account.create!(name: "No Scribe Account", slug: "no-scribe")
    set_tenant(account_without_scribe)
    user2 = account_without_scribe.users.create!(email: "user2@example.com", password: "password123")

    conv = account_without_scribe.conversations.create!(
      title: "Test",
      user: user2,
      conversation_type: :adhoc,
      space: account_without_scribe.spaces.create!(name: "No Scribe Space")
    )

    conv.ensure_scribe_present!

    assert_not conv.has_scribe?
  end

  # ============================================================================
  # PARTICIPANT QUERIES
  # ============================================================================

  test "advisor_participants returns only non-scribe participants" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    p1 = conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    p2 = conv.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 1)
    conv.conversation_participants.create!(advisor: @scribe, role: :scribe)

    advisors = conv.advisor_participants
    assert_includes advisors, p1
    assert_includes advisors, p2
    assert_equal 2, advisors.count
  end

  test "participant_advisors returns only non-scribe advisors" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conv.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 1)
    conv.conversation_participants.create!(advisor: @scribe, role: :scribe)

    advisors = conv.participant_advisors
    assert_includes advisors, @advisor1
    assert_includes advisors, @advisor2
    assert_not_includes advisors, @scribe
    assert_equal 2, advisors.length
  end

  test "add_advisor adds new advisor to conversation" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_not_includes conv.advisors, @advisor2

    result = conv.add_advisor(@advisor2)

    assert result
    assert_includes conv.advisors.reload, @advisor2
  end

  test "add_advisor returns false for duplicate advisor" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    result = conv.add_advisor(@advisor1)

    assert_not result
  end

  test "add_advisor returns false for scribe" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    result = conv.add_advisor(@scribe)

    assert_not result
  end

  # ============================================================================
  # MAX DEPTH METHODS
  # ============================================================================

  test "max_depth returns 1 for open roe" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      roe_type: :open,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_equal 1, conv.max_depth
  end

  test "max_depth returns 2 for consensus roe" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      roe_type: :consensus,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_equal 2, conv.max_depth
  end

  test "max_depth returns 2 for brainstorming roe" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      roe_type: :brainstorming,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_equal 2, conv.max_depth
  end

  test "max_depth returns 1 for unknown roe type" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      roe_type: :open,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    # Manually set an invalid roe_type to test the else branch
    conv.update_column(:roe_type, "unknown")
    assert_equal 1, conv.max_depth
  end

  # ============================================================================
  # STATUS METHODS AND CALLBACKS
  # ============================================================================

  test "status defaults to active" do
    conv = @account.conversations.new(
      title: "Test",
      user: @user,
      council: @council,
      space: @space
    )
    conv.save(validate: false)
    assert_equal "active", conv.status
  end

  test "active? returns true for active status" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      status: :active,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    assert conv.active?
  end

  test "concluding? returns true for concluding status" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      status: :concluding,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    assert conv.concluding?
  end

  test "resolved? returns true for resolved status" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      status: :resolved,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    assert conv.resolved?
  end

  test "archived? returns true for archived status" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      status: :archived,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    assert conv.archived?
  end

  test "status can transition between states" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      status: :active,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    conv.concluding!
    assert conv.concluding?

    conv.resolved!
    assert conv.resolved?

    conv.archived!
    assert conv.archived?
  end

  # ============================================================================
  # MEMORY AND CONTEXT METHODS
  # ============================================================================

  test "memory_data returns empty hash for blank memory" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert_equal({}, conv.memory_data)
  end

  test "memory_data returns empty hash for nil memory" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conv.update_column(:memory, nil)

    assert_equal({}, conv.memory_data)
  end

  test "memory_data parses JSON string" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conv.update!(memory: '{"key": "value", "number": 42}')

    data = conv.memory_data
    assert_equal "value", data["key"]
    assert_equal 42, data["number"]
  end

  test "memory_data handles encrypted hash input" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    # When using encrypted attributes, Rails stores the ciphertext
    # and returns the decrypted value. The memory_data method handles
    # the decrypted value which can be a hash.
    conv.update!(memory: { "key" => "value" }.to_json)
    data = conv.memory_data
    assert_equal "value", data["key"]
  end

  test "memory_data returns empty hash for invalid JSON" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)
    conv.update_column(:memory, "not valid json {{{")

    assert_equal({}, conv.memory_data)
  end

  test "increment_scribe_initiated_count! increases count by 1" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      scribe_initiated_count: 0,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    conv.increment_scribe_initiated_count!
    assert_equal 1, conv.reload.scribe_initiated_count

    conv.increment_scribe_initiated_count!
    assert_equal 2, conv.reload.scribe_initiated_count
  end

  test "reset_scribe_initiated_count! sets count to 0" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      scribe_initiated_count: 5,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    conv.reset_scribe_initiated_count!
    assert_equal 0, conv.reload.scribe_initiated_count
  end

  test "clear_responded_advisors removes responded_advisor_ids from context" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      context: { "responded_advisor_ids" => [ "1", "2", "3" ], "other_key" => "value" },
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    conv.clear_responded_advisors

    assert_nil conv.reload.context["responded_advisor_ids"]
    assert_equal "value", conv.context["other_key"]  # Other keys preserved
  end

  # ============================================================================
  # VALIDATIONS
  # ============================================================================

  test "invalid without at least one advisor on update" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      space: @space
    )
    # Skip validation on create
    conv.save(validate: false)

    # Should fail on update without advisors
    conv.title = "New Title"
    assert_not conv.valid?
    assert_includes conv.errors[:advisors], "must have at least one advisor"
  end

  test "valid with at least one non-scribe advisor" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    assert conv.valid?
  end

  test "invalid with only scribe advisor" do
    conv = @account.conversations.create!(
      title: "Test",
      user: @user,
      council: @council,
      space: @space
    )
    conv.conversation_participants.create!(advisor: @scribe, role: :scribe)

    assert_not conv.valid?
    assert_includes conv.errors[:advisors], "must have at least one advisor"
  end

  test "council is required for council_meeting type" do
    conv = @account.conversations.new(
      title: "Test",
      user: @user,
      conversation_type: :council_meeting,
      space: @space
    )
    conv.conversation_participants.build(advisor: @advisor1, role: :advisor, position: 0)

    assert_not conv.valid?
    assert_includes conv.errors[:council], "can't be blank"
  end

  test "council is not required for adhoc type" do
    conv = @account.conversations.new(
      title: "Test",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conv.conversation_participants.build(advisor: @advisor1, role: :advisor, position: 0)

    assert conv.valid?
  end

  # ============================================================================
  # SCOPES
  # ============================================================================

  test "recent scope orders by last_message_at" do
    conv1 = @account.conversations.create!(
      title: "Conv 1",
      user: @user,
      council: @council,
      last_message_at: 1.day.ago,
      space: @space
    )
    conv1.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    conv2 = @account.conversations.create!(
      title: "Conv 2",
      user: @user,
      council: @council,
      last_message_at: 1.hour.ago,
      space: @space
    )
    conv2.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 0)

    conv3 = @account.conversations.create!(
      title: "Conv 3",
      user: @user,
      council: @council,
      last_message_at: 1.minute.ago,
      space: @space
    )
    advisor3 = @account.advisors.create!(
      name: "Third Advisor",
      system_prompt: "You are third.",
      space: @space,
      llm_model: @llm_model
    )
    conv3.conversation_participants.create!(advisor: advisor3, role: :advisor, position: 0)

    ordered = Conversation.recent.to_a
    assert_equal [ conv3, conv2, conv1 ], ordered
  end

  test "active scope filters by status" do
    active_conv = @account.conversations.create!(
      title: "Active",
      user: @user,
      council: @council,
      status: :active,
      space: @space
    )
    active_conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    archived_conv = @account.conversations.create!(
      title: "Archived",
      user: @user,
      council: @council,
      status: :archived,
      space: @space
    )
    archived_conv.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 0)

    actives = Conversation.active.to_a
    assert_includes actives, active_conv
    assert_not_includes actives, archived_conv
  end

  test "adhoc_conversations scope filters by type" do
    adhoc_conv = @account.conversations.create!(
      title: "Adhoc",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    adhoc_conv.conversation_participants.create!(advisor: @advisor1, role: :advisor, position: 0)

    council_conv = @account.conversations.create!(
      title: "Council",
      user: @user,
      council: @council,
      conversation_type: :council_meeting,
      space: @space
    )
    council_conv.conversation_participants.create!(advisor: @advisor2, role: :advisor, position: 0)

    adhocs = Conversation.adhoc_conversations.to_a
    assert_includes adhocs, adhoc_conv
    assert_not_includes adhocs, council_conv
  end
end
