require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-account-conversations")
    set_tenant(@account)
    @user = @account.users.create!(email: "user@example.com", password: "password123")
    @space = @account.spaces.create!(name: "Test Space")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

    # Create provider and LLM model for advisors
    provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )
    llm_model = provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )

    # Create an advisor for conversations
    @advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      space: @space,
      llm_model: llm_model
    )
  end

  # Validation tests
  test "valid with account, council, user, and title" do
    conversation = @account.conversations.new(council: @council, user: @user, title: "Test", space: @space)
    assert conversation.valid?
  end

  test "invalid without title" do
    conversation = @account.conversations.new(council: @council, user: @user, space: @space)
    assert_not conversation.valid?
    assert_includes conversation.errors[:title], "can't be blank"
  end

  test "invalid without account" do
    ActsAsTenant.without_tenant do
      conversation = Conversation.new(council: @council, user: @user, title: "Test", space: @space)
      assert_not conversation.valid?
      assert_includes conversation.errors[:account], "can't be blank"
    end
  end

  test "invalid without council" do
    conversation = @account.conversations.new(user: @user, title: "Test", space: @space)
    assert_not conversation.valid?
    assert_includes conversation.errors[:council], "can't be blank"
  end

  test "invalid without user" do
    conversation = @account.conversations.new(council: @council, title: "Test", space: @space)
    assert_not conversation.valid?
    assert_includes conversation.errors[:user], "can't be blank"
  end

  # Helper to create conversation with advisor
  def create_conversation_with_advisor(attrs = {})
    conversation = @account.conversations.new(
      council: @council,
      user: @user,
      title: "Test Conversation",
      space: @space,
      **attrs
    )
    conversation.save(validate: false) # Skip validation on create
    conversation.conversation_participants.create!(
      advisor: @advisor,
      role: :advisor,
      position: 0
    )
    conversation
  end
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
    conversation = @account.conversations.create!(council: @council, user: @user, title: "Test", space: @space)
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
    conversation = @account.conversations.create!(council: @council, user: @user, title: "Test", space: @space)
    assert_equal "active", conversation.status
    assert conversation.active?
  end

  test "can be set to archived status" do
    conversation = @account.conversations.create!(council: @council, user: @user, title: "Test", status: "archived", space: @space)
    assert_equal "archived", conversation.status
    assert conversation.archived?
  end

  test "status enum methods work" do
    conversation = create_conversation_with_advisor
    assert conversation.active?
    assert_not conversation.archived?

    conversation.archived!
    assert conversation.archived?
    assert_not conversation.active?
  end

  test "invalid status raises ArgumentError" do
    assert_raises(ArgumentError) do
      @account.conversations.create!(council: @council, user: @user, title: "Test", status: "deleted", space: @space)
    end
  end

  test "valid status values are active, resolved, and archived" do
    expected = { "active" => "active", "resolved" => "resolved", "archived" => "archived" }
    assert_equal(expected, Conversation.statuses)
  end

  # Scope tests
  test "recent scope orders by updated_at descending" do
    conv1 = @account.conversations.create!(council: @council, user: @user, title: "Conv 1", last_message_at: 1.hour.ago, space: @space)
    conv2 = @account.conversations.create!(council: @council, user: @user, title: "Conv 2", last_message_at: 1.minute.ago, space: @space)
    conv3 = @account.conversations.create!(council: @council, user: @user, title: "Conv 3", last_message_at: 1.day.ago, space: @space)

    conv1.touch
    conv2.touch
    conv3.touch

    conv1.update_column(:updated_at, 2.hours.ago)
    conv2.update_column(:updated_at, 1.minute.ago)
    conv3.update_column(:updated_at, 1.day.ago)

    ordered = Conversation.recent.to_a
    assert_equal [ conv2, conv1, conv3 ], ordered
  end

  test "recent scope handles nil last_message_at" do
    conv1 = @account.conversations.create!(council: @council, user: @user, title: "Conv 1", last_message_at: 1.hour.ago, space: @space)
    conv2 = @account.conversations.create!(council: @council, user: @user, title: "Conv 2", last_message_at: nil, space: @space)

    ordered = Conversation.recent.to_a
    # nil values typically sort last in descending order in PostgreSQL
    assert_includes ordered, conv1
    assert_includes ordered, conv2
  end

  test "active scope returns only active conversations" do
    active_conv = @account.conversations.create!(council: @council, user: @user, title: "Active", status: "active", space: @space)
    archived_conv = @account.conversations.create!(council: @council, user: @user, title: "Archived", status: "archived", space: @space)

    actives = Conversation.active.to_a
    assert_includes actives, active_conv
    assert_not_includes actives, archived_conv
  end

  test "active scope excludes archived conversations" do
    @account.conversations.create!(council: @council, user: @user, title: "Archived", status: "archived", space: @space)
    assert_empty Conversation.active
  end

  # RoE type tests
  test "has roe_type enum with default open" do
    conversation = create_conversation_with_advisor
    assert_equal "open", conversation.roe_type
    assert conversation.open?
  end

  test "title_locked defaults to false" do
    conversation = create_conversation_with_advisor
    assert_equal false, conversation.title_locked
  end

  test "deletable_by? allows conversation starter" do
    conversation = create_conversation_with_advisor
    assert conversation.deletable_by?(@user)
  end

  test "deletable_by? allows council creator" do
    other_user = @account.users.create!(email: "other-delete@example.com", password: "password123")
    conversation = @account.conversations.create!(
      council: @council,
      user: other_user,
      title: "Delete Policy",
      space: @space
    )
    conversation.conversation_participants.create!(advisor: @advisor, role: :advisor, position: 0)

    assert conversation.deletable_by?(@user)
  end

  test "can change roe_type" do
    conversation = create_conversation_with_advisor
    conversation.update!(roe_type: :consensus)
    assert conversation.consensus?
  end

  test "roe_type includes all expected values" do
    expected = %w[open consensus brainstorming]
    assert_equal expected.sort, Conversation.roe_types.keys.sort
  end

  test "max_depth for open RoE is 1" do
    conversation = create_conversation_with_advisor(roe_type: :open)
    assert_equal 1, conversation.max_depth
  end

  test "max_depth for consensus RoE is 5" do
    conversation = create_conversation_with_advisor(roe_type: :consensus)
    assert_equal 5, conversation.max_depth
  end

  test "max_depth for brainstorming RoE is 2" do
    conversation = create_conversation_with_advisor(roe_type: :brainstorming)
    assert_equal 2, conversation.max_depth
  end

  # max_depth else branch (no roe_type match)
  test "max_depth returns 1 for unknown roe_type via raw update" do
    conversation = create_conversation_with_advisor(roe_type: :open)
    # Bypass enum to set an invalid/unknown value directly
    conversation.update_column(:roe_type, "unknown_type")
    assert_equal 1, conversation.max_depth
  end

  # memory_data tests
  test "memory_data returns empty hash when memory is blank" do
    conversation = create_conversation_with_advisor
    # memory defaults to nil/blank
    assert_equal({}, conversation.memory_data)
  end

  test "memory_data parses JSON string memory" do
    conversation = create_conversation_with_advisor
    conversation.update_column(:memory, '{"key":"value"}')
    assert_equal({ "key" => "value" }, conversation.memory_data)
  end

  test "memory_data returns empty hash on JSON parse error" do
    conversation = create_conversation_with_advisor
    conversation.update_column(:memory, "not valid json {{{")
    assert_equal({}, conversation.memory_data)
  end

  test "assign_space_from_council sets space when missing and council exists" do
    conversation = @account.conversations.new(council: @council, user: @user, title: "From council")

    conversation.valid?

    assert_equal @space, conversation.space
  end

  test "assign_space_from_council does not overwrite explicit space" do
    other_space = @account.spaces.create!(name: "Other")
    conversation = @account.conversations.new(council: @council, user: @user, title: "Keep", space: other_space)

    conversation.valid?

    assert_equal other_space, conversation.space
  end

  test "memory_data returns hash memory as-is" do
    conversation = create_conversation_with_advisor
    payload = { "summary" => "x" }
    conversation.stubs(:memory).returns(payload)

    assert_equal payload, conversation.memory_data
  end

  test "scribe initiated helpers increment and reset" do
    conversation = create_conversation_with_advisor

    assert_equal 0, conversation.scribe_initiated_count

    conversation.increment_scribe_initiated_count!
    assert_equal 1, conversation.reload.scribe_initiated_count

    conversation.reset_scribe_initiated_count!
    assert_equal 0, conversation.reload.scribe_initiated_count
  end

  test "deletable_by? returns false for nil user" do
    conversation = create_conversation_with_advisor

    assert_equal false, conversation.deletable_by?(nil)
  end

  test "add_advisor returns false when advisor already included" do
    conversation = create_conversation_with_advisor

    assert_equal false, conversation.add_advisor(@advisor)
  end

  test "add_advisor returns false for scribe advisor" do
    conversation = create_conversation_with_advisor
    scribe = @account.advisors.create!(
      name: "scribe-only",
      system_prompt: "scribe",
      space: @space,
      llm_model: @advisor.llm_model,
      is_scribe: true
    )

    assert_equal false, conversation.add_advisor(scribe)
  end

  test "ensure_scribe_present! no-ops when scribe cannot be resolved" do
    conversation = create_conversation_with_advisor
    conversation.stubs(:has_scribe?).returns(false)
    conversation.space.stubs(:scribe_advisor).returns(nil)

    assert_no_difference "ConversationParticipant.count" do
      conversation.ensure_scribe_present!
    end
  end

  test "adhoc_conversations scope returns only adhoc rows" do
    adhoc = @account.conversations.create!(title: "Adhoc", user: @user, conversation_type: :adhoc, space: @space)
    council = @account.conversations.create!(title: "Council", user: @user, council: @council, conversation_type: :council_meeting, space: @space)

    assert_includes Conversation.adhoc_conversations, adhoc
    assert_not_includes Conversation.adhoc_conversations, council
  end
end
