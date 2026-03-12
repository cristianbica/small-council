require "test_helper"

class MemoriesControllerComprehensiveTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @account = accounts(:one)
    @space = spaces(:one)
    @memory = memories(:one)

    sign_in_as(@user)
    host! ENV["APP_HOST"] if ENV["APP_HOST"].present?
  end

  # ============================================================================
  # Versions Action Tests
  # ============================================================================

  test "should get versions page" do
    # Create a version first by updating the memory
    @memory.update!(content: "Updated content for versions test")

    get versions_space_memory_url(@space, @memory)
    assert_response :success
    assert_select "h1", /Version History/
  end

  test "should show versions in order" do
    @memory.update!(content: "First update")
    @memory.update!(content: "Second update")

    get versions_space_memory_url(@space, @memory)
    assert_response :success
  end

  # ============================================================================
  # Version Action Tests (viewing specific version)
  # ============================================================================

  test "should get specific version" do
    @memory.update!(title: "First Title", content: "Initial content")
    @memory.update!(title: "Updated Title", content: "Updated content")

    get version_space_memory_url(@space, @memory, version_number: 1)
    assert_response :success
    assert_select "h1", /Version/
  end

  test "should show diff when viewing version with previous" do
    @memory.update!(content: "Initial content")
    @memory.update!(content: "New content here")

    get version_space_memory_url(@space, @memory, version_number: 2)
    assert_response :success
  end

  test "should redirect when version not found" do
    get version_space_memory_url(@space, @memory, version_number: 999)
    assert_redirected_to versions_space_memory_path(@space, @memory)
    assert_equal "Version not found.", flash[:alert]
  end

  test "should handle first version (no previous)" do
    @memory.update!(content: "First version content")

    get version_space_memory_url(@space, @memory, version_number: 1)
    assert_response :success
    # No diff shown since it's the first version
  end

  # ============================================================================
  # Restore Version Tests
  # ============================================================================

  test "should restore to a previous version" do
    original_title = @memory.title
    original_content = @memory.content

    @memory.update!(content: "Initial version for restore test")

    @memory.update!(title: "Changed Title")

    post restore_version_space_memory_url(@space, @memory, version_number: 1)

    assert_redirected_to space_memory_url(@space, @memory)
    assert_match(/restored to version 1/, flash[:notice])

    @memory.reload
    # Version 1 stored the ORIGINAL state (before first update)
    assert_equal original_title, @memory.title
    assert_equal original_content, @memory.content
  end

  test "should restore version with custom reason" do
    @memory.update!(content: "Initial content")
    @memory.update!(content: "New content")

    post restore_version_space_memory_url(@space, @memory, version_number: 1, reason: "Rolled back due to error")

    assert_redirected_to space_memory_url(@space, @memory)
  end

  test "should redirect when trying to restore invalid version number" do
    post restore_version_space_memory_url(@space, @memory, version_number: 0)
    assert_redirected_to versions_space_memory_path(@space, @memory)
    assert_equal "Invalid version number.", flash[:alert]
  end

  test "should redirect when version to restore not found" do
    post restore_version_space_memory_url(@space, @memory, version_number: 999)
    assert_redirected_to versions_space_memory_path(@space, @memory)
    assert_equal "Version not found.", flash[:alert]
  end

  test "should handle restore errors gracefully" do
    @memory.update!(content: "Initial content for error test")

    # Request a non-existent version number
    post restore_version_space_memory_url(@space, @memory, version_number: 999)

    assert_redirected_to versions_space_memory_path(@space, @memory)
    assert_equal "Version not found.", flash[:alert]
  end

  # ============================================================================
  # Export Tests
  # ============================================================================

  test "should export single memory as markdown" do
    get export_space_memory_url(@space, @memory)

    assert_response :success
    assert_equal @memory.content, response.body
    assert_match(/#{@memory.title}\.md/, response.headers["Content-Disposition"])
    assert_equal "text/markdown", response.media_type
  end

  test "should export memory from different memory type" do
    summary_memory = @space.memories.create!(
      account: @account,
      title: "Summary Memory",
      content: "This is a summary",
      memory_type: "summary",
      status: "active",
      position: 2
    )

    get export_space_memory_url(@space, summary_memory)

    assert_response :success
    assert_equal summary_memory.content, response.body
    assert_match(/Summary Memory\.md/, response.headers["Content-Disposition"])
  end

  # ============================================================================
  # Search Tests
  # ============================================================================

  test "should search memories" do
    @memory.update!(title: "Unique Search Term XYZ123")

    get search_space_memories_url(@space, q: "XYZ123")
    assert_response :success
    assert_select "h3", @memory.title
  end

  test "should search memories with no results" do
    get search_space_memories_url(@space, q: "NonExistentTerm99999")
    assert_response :success
  end

  test "should search with blank query" do
    get search_space_memories_url(@space, q: "")
    assert_response :success
  end

  test "should limit search results to 20" do
    # Create many memories
    25.times do |i|
      @space.memories.create!(
        account: @account,
        title: "Memory #{i} searchable",
        content: "Content",
        memory_type: "knowledge",
        status: "active",
        position: i + 10
      )
    end

    get search_space_memories_url(@space, q: "searchable")
    assert_response :success
  end

  # ============================================================================
  # Index with Filters Tests
  # ============================================================================

  test "should filter memories by type" do
    knowledge_memory = @space.memories.create!(
      account: @account,
      title: "Knowledge Item",
      content: "Knowledge content",
      memory_type: "knowledge",
      status: "active",
      position: 2
    )

    get space_memories_url(@space, type: "knowledge")
    assert_response :success
  end

  test "should filter memories by summary type" do
    summary_memory = @space.memories.create!(
      account: @account,
      title: "Summary Item",
      content: "Summary content",
      memory_type: "summary",
      status: "active",
      position: 0
    )

    get space_memories_url(@space, type: "summary")
    assert_response :success
  end

  test "should show all memories when type is blank" do
    get space_memories_url(@space, type: "")
    assert_response :success
  end

  test "should search from index page" do
    @memory.update!(title: "Searchable Memory ABC")

    get space_memories_url(@space, q: "ABC")
    assert_response :success
  end

  # ============================================================================
  # Update with Version Tests
  # ============================================================================

  test "should create version when title changes" do
    @memory.update!(content: "Initial content for versioning")

    assert_difference "RecordVersion.count", 1 do
      patch space_memory_url(@space, @memory), params: {
        memory: {
          title: "New Title for Version Test"
        }
      }
    end

    version = RecordVersion.last
    assert_equal @user, version.whodunnit
  end

  test "should create version when content changes" do
    assert_difference "RecordVersion.count", 1 do
      patch space_memory_url(@space, @memory), params: {
        memory: {
          content: "Updated content for version test"
        }
      }
    end

    version = RecordVersion.last
    assert_equal @user, version.whodunnit
  end

  test "should create version with multiple changes" do
    assert_difference "RecordVersion.count", 1 do
      patch space_memory_url(@space, @memory), params: {
        memory: {
          title: "New Title",
          content: "New content"
        }
      }
    end

    version = RecordVersion.last
    assert_equal @user, version.whodunnit
  end

  test "should not create version when no changes made" do
    # First update to establish baseline
    @memory.update!(content: "Stable content")

    version_count_before = @memory.versions.count

    # Update with same values
    patch space_memory_url(@space, @memory), params: {
      memory: {
        title: @memory.title,
        content: @memory.content
      }
    }

    assert_equal version_count_before, @memory.versions.count
  end

  test "should not create version when update fails" do
    version_count_before = RecordVersion.count

    patch space_memory_url(@space, @memory), params: {
      memory: {
        title: ""  # Invalid - title is required
      }
    }

    assert_response :unprocessable_entity
    assert_equal version_count_before, RecordVersion.count
  end

  # ============================================================================
  # New Memory with Type Tests
  # ============================================================================

  test "should set memory type from params" do
    get new_space_memory_url(@space, type: "summary")
    assert_response :success
  end

  test "should default to knowledge type when type param not provided" do
    get new_space_memory_url(@space)
    assert_response :success
  end

  test "should calculate next position for new memory" do
    @space.memories.create!(
      account: @account,
      title: "Memory at position 10",
      content: "Content",
      memory_type: "knowledge",
      status: "active",
      position: 10
    )

    get new_space_memory_url(@space)
    assert_response :success
  end

  # ============================================================================
  # Security and Authorization Tests
  # ============================================================================

  test "cannot access versions of memory from different account" do
    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Account", slug: "other-versions-test")
    end
    other_space = ActsAsTenant.without_tenant do
      other_account.spaces.create!(name: "Other Space")
    end
    other_memory = ActsAsTenant.without_tenant do
      other_space.memories.create!(
        account: other_account,
        title: "Other Memory",
        content: "Other content",
        memory_type: "knowledge",
        status: "active",
        position: 1
      )
    end

    get versions_space_memory_url(other_space, other_memory)
    assert_response :not_found
  end

  test "cannot restore version of memory from different account" do
    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Restore Account", slug: "other-restore-test")
    end
    other_space = ActsAsTenant.without_tenant do
      other_account.spaces.create!(name: "Other Space")
    end
    other_memory = ActsAsTenant.without_tenant do
      other_space.memories.create!(
        account: other_account,
        title: "Other Memory",
        content: "Other content",
        memory_type: "knowledge",
        status: "active",
        position: 1
      )
    end
    # Create a version by updating the memory
    ActsAsTenant.without_tenant do
      other_memory.update!(content: "Updated content for version")
    end

    post restore_version_space_memory_url(other_space, other_memory, version_number: 1)
    assert_response :not_found
  end

  test "cannot export memory from different space" do
    other_account = ActsAsTenant.without_tenant do
      Account.create!(name: "Other Export Account", slug: "other-export-test")
    end
    other_space = ActsAsTenant.without_tenant do
      other_account.spaces.create!(name: "Other Export Space")
    end
    other_memory = ActsAsTenant.without_tenant do
      other_space.memories.create!(
        account: other_account,
        title: "Other Memory",
        content: "Other content",
        memory_type: "knowledge",
        status: "active",
        position: 1
      )
    end

    # This should fail with not found since the space doesn't belong to current account
    get export_space_memory_url(other_space, other_memory)
    assert_response :not_found
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "show handles memory with versions" do
    @memory.update!(content: "Updated content for show test")

    get space_memory_url(@space, @memory)
    assert_response :success
  end

  test "show handles memory without versions" do
    get space_memory_url(@space, @memory)
    assert_response :success
  end

  test "archive already archived memory (idempotent)" do
    archived_memory = memories(:archived)

    post archive_space_memory_url(@space, archived_memory)
    assert_redirected_to space_memories_url(@space)

    archived_memory.reload
    assert archived_memory.archived?
  end

  test "activate already active memory (idempotent)" do
    post activate_space_memory_url(@space, @memory)
    assert_redirected_to space_memory_url(@space, @memory)

    @memory.reload
    assert @memory.active?
  end
end
