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

  # Helper to create conversation with advisor
  def create_conversation_with_advisor(attrs = {})
    conversation = @account.conversations.new(
      council: @council,
      user: @user,
      title: "Test Conversation",
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
    conversation = create_conversation_with_advisor
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

  test "valid status values are active, concluding, resolved, and archived" do
    expected = { "active" => "active", "concluding" => "concluding", "resolved" => "resolved", "archived" => "archived" }
    assert_equal(expected, Conversation.statuses)
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

  # RoE type tests
  test "has roe_type enum with default open" do
    conversation = create_conversation_with_advisor
    assert_equal "open", conversation.roe_type
    assert conversation.open?
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

  test "max_depth for consensus RoE is 2" do
    conversation = create_conversation_with_advisor(roe_type: :consensus)
    assert_equal 2, conversation.max_depth
  end

  test "max_depth for brainstorming RoE is 2" do
    conversation = create_conversation_with_advisor(roe_type: :brainstorming)
    assert_equal 2, conversation.max_depth
  end

  test "last_advisor_id reads from context" do
    conversation = create_conversation_with_advisor
    conversation.update!(context: { "last_advisor_id" => 42 })
    assert_equal 42, conversation.last_advisor_id
  end

  test "mark_advisor_spoken updates context" do
    conversation = create_conversation_with_advisor
    conversation.mark_advisor_spoken(99)
    assert_equal 99, conversation.reload.context["last_advisor_id"]
  end

  # max_depth else branch (no roe_type match)
  test "max_depth returns 1 for unknown roe_type via raw update" do
    conversation = create_conversation_with_advisor(roe_type: :open)
    # Bypass enum to set an invalid/unknown value directly
    conversation.update_column(:roe_type, "unknown_type")
    assert_equal 1, conversation.max_depth
  end

  # advisor_has_responded? branch tests
  test "advisor_has_responded? returns nil when context key is absent" do
    conversation = create_conversation_with_advisor
    # No responded_advisor_ids key in context — &.include? returns nil (falsy)
    assert_not conversation.advisor_has_responded?(@advisor.id)
  end

  test "advisor_has_responded? returns true when advisor has responded" do
    conversation = create_conversation_with_advisor
    conversation.mark_advisor_responded(@advisor.id)
    assert conversation.advisor_has_responded?(@advisor.id)
  end

  # mark_advisor_responded branch tests
  test "mark_advisor_responded initializes array when context key absent" do
    conversation = create_conversation_with_advisor
    conversation.mark_advisor_responded(@advisor.id)
    assert_includes conversation.reload.context["responded_advisor_ids"], @advisor.id.to_s
  end

  test "mark_advisor_responded appends to existing array" do
    conversation = create_conversation_with_advisor
    conversation.mark_advisor_responded(@advisor.id)

    other_provider = @account.providers.create!(name: "P2", provider_type: "openai", api_key: "k2")
    other_model = other_provider.llm_models.create!(account: @account, name: "GPT2", identifier: "gpt-2")
    other_advisor = @account.advisors.create!(
      name: "Other Advisor", system_prompt: "Other", space: @space, llm_model: other_model
    )
    conversation.mark_advisor_responded(other_advisor.id)
    ids = conversation.reload.context["responded_advisor_ids"]
    assert_includes ids, @advisor.id.to_s
    assert_includes ids, other_advisor.id.to_s
  end

  # all_advisors_responded? tests
  test "all_advisors_responded? returns false when no one has responded" do
    conversation = create_conversation_with_advisor
    assert_not conversation.all_advisors_responded?
  end

  test "all_advisors_responded? returns true when all advisors responded" do
    conversation = create_conversation_with_advisor
    conversation.mark_advisor_responded(@advisor.id)
    assert conversation.all_advisors_responded?
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
end
