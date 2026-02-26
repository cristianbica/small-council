require "test_helper"

class MemoryTest < ActiveSupport::TestCase
  fixtures :accounts, :spaces, :memories, :users

  setup do
    @account = accounts(:one)
    @space = spaces(:one)
    @user = users(:one)
    set_tenant(@account)
  end

  test "should be valid with all required attributes" do
    memory = @space.memories.new(
      account: @account,
      title: "Test Memory",
      content: "This is a test memory.",
      memory_type: "knowledge"
    )
    assert memory.valid?, "Memory should be valid with all required attributes"
  end

  test "should require title" do
    memory = @space.memories.new(
      account: @account,
      title: "",
      content: "Content here",
      memory_type: "knowledge"
    )
    assert_not memory.valid?, "Memory should not be valid without title"
    assert_includes memory.errors[:title], "can't be blank"
  end

  test "should require content" do
    memory = @space.memories.new(
      account: @account,
      title: "Test",
      content: "",
      memory_type: "knowledge"
    )
    assert_not memory.valid?, "Memory should not be valid without content"
    assert_includes memory.errors[:content], "can't be blank"
  end

  test "should require memory_type" do
    memory = @space.memories.new(
      account: @account,
      title: "Test",
      content: "Content",
      memory_type: ""
    )
    assert_not memory.valid?, "Memory should not be valid without memory_type"
  end

  test "should only allow valid memory types" do
    valid_types = %w[summary conversation_summary conversation_notes knowledge]
    valid_types.each do |type|
      memory = @space.memories.new(
        account: @account,
        title: "Test",
        content: "Content",
        memory_type: type
      )
      assert memory.valid?, "Memory should be valid with type: #{type}"
    end

    invalid_memory = @space.memories.new(
      account: @account,
      title: "Test",
      content: "Content",
      memory_type: "invalid_type"
    )
    assert_not invalid_memory.valid?, "Memory should not be valid with invalid type"
  end

  test "should only allow valid statuses" do
    valid_statuses = %w[active archived draft]
    valid_statuses.each do |status|
      memory = @space.memories.new(
        account: @account,
        title: "Test",
        content: "Content",
        memory_type: "knowledge",
        status: status
      )
      assert memory.valid?, "Memory should be valid with status: #{status}"
    end

    invalid_memory = @space.memories.new(
      account: @account,
      title: "Test",
      content: "Content",
      memory_type: "knowledge",
      status: "invalid_status"
    )
    assert_not invalid_memory.valid?, "Memory should not be valid with invalid status"
  end

  test "should belong to account and space" do
    memory = memories(:one)
    assert_equal @account, memory.account
    assert_equal @space, memory.space
  end

  test "summary? predicate should return true only for summary type" do
    summary = memories(:summary)
    knowledge = memories(:one)

    assert summary.summary?, "Summary memory should return true for summary?"
    assert_not knowledge.summary?, "Knowledge memory should return false for summary?"
  end

  test "active? predicate should return true only for active status" do
    active = memories(:one)
    archived = memories(:archived)

    assert active.active?, "Active memory should return true for active?"
    assert_not archived.active?, "Archived memory should return false for active?"
  end

  test "archive! should update status to archived" do
    memory = memories(:one)
    user = users(:one)

    assert memory.active?
    memory.archive!(user)
    assert memory.archived?
    assert_equal user, memory.updated_by
  end

  test "activate! should update status to active" do
    memory = memories(:archived)
    user = users(:one)

    assert memory.archived?
    memory.activate!(user)
    assert memory.active?
    assert_equal user, memory.updated_by
  end

  test "content_preview should return truncated content" do
    memory = memories(:one)
    memory.update!(content: "a" * 1000)

    preview = memory.content_preview(length: 200)
    assert_equal 200, preview.length
    assert preview.end_with?("...")
  end

  test "primary_summary_for should return the most recent active summary" do
    # Create two summaries
    old_summary = @space.memories.create!(
      account: @account,
      title: "Old Summary",
      content: "Old content",
      memory_type: "summary",
      status: "active",
      updated_at: 1.day.ago
    )

    new_summary = @space.memories.create!(
      account: @account,
      title: "New Summary",
      content: "New content",
      memory_type: "summary",
      status: "active",
      updated_at: Time.current
    )

    result = Memory.primary_summary_for(@space)
    assert_equal new_summary, result, "Should return the most recently updated summary"
  end

  test "primary_summary_for should not return archived summaries" do
    # Archive the existing summary fixture
    summary = memories(:summary)
    summary.archive!(@user)

    result = Memory.primary_summary_for(@space)
    assert_nil result, "Should not return archived summaries"
  end

  test "create_primary_summary! should create a summary memory" do
    user = users(:one)
    memory = Memory.create_primary_summary!(
      space: @space,
      title: "Space Overview",
      content: "Overview content",
      creator: user
    )

    assert memory.persisted?
    assert_equal "summary", memory.memory_type
    assert_equal "active", memory.status
    assert_equal user, memory.created_by
  end

  test "create_conversation_summary! should create linked memory" do
    # Create a council and conversation directly
    council = @space.councils.create!(
      account: @account,
      user: @user,
      name: "Test Council",
      description: "Test council"
    )
    conversation = council.conversations.create!(
      account: @account,
      user: @user,
      title: "Test Conversation"
    )

    memory = Memory.create_conversation_summary!(
      conversation: conversation,
      title: "Discussion Summary",
      content: "Summary content",
      creator: @user
    )

    assert memory.persisted?
    assert_equal "conversation_summary", memory.memory_type
    assert_equal conversation, memory.source
    assert_equal conversation.council.space, memory.space
  end

  test "search scope should find by title" do
    memory = memories(:one)
    memory.update!(title: "Unique Searchable Title XYZ123")

    results = @space.memories.search("XYZ123")
    assert_includes results, memory
  end

  # Note: Content search is limited because content is encrypted at rest.
  # The search scope searches both fields but encrypted content won't match
  # until it's decrypted. For now, we primarily rely on title search.
  test "search scope returns all when query is blank" do
    results = @space.memories.search("")
    assert_equal @space.memories.count, results.count
  end

  test "tenant scoping should isolate memories by account" do
    memory = memories(:one)
    set_tenant(accounts(:two))

    assert_raises(ActiveRecord::RecordNotFound) do
      Memory.find(memory.id)
    end
  end
end
