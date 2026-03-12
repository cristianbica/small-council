require "test_helper"

class VersionableConcernTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @space = spaces(:one)
    @user = users(:one)
    set_tenant(@account)
  end

  test "versions are created on update" do
    memory = @space.memories.create!(
      account: @account,
      title: "Test Memory",
      content: "Original content",
      memory_type: "knowledge",
      status: "active"
    )

    assert_equal 0, memory.versions.count, "No versions should exist initially"

    # Update creates a version
    memory.update!(content: "Updated content")
    assert_equal 1, memory.versions.count, "Version should be created on update"

    version = memory.versions.first
    assert_equal 1, version.version_number
    assert_equal "Original content", version.attribute_value(:content), "Version stores previous state"
    assert_equal "Test Memory", version.attribute_value(:title)
  end

  test "versions store only tracked attributes" do
    memory = @space.memories.create!(
      account: @account,
      title: "Test Memory",
      content: "Original content",
      memory_type: "knowledge",
      status: "active",
      position: 1
    )

    memory.update!(content: "Updated content")

    version = memory.versions.first
    # Position is not in track_versions list
    assert_nil version.attribute_value(:position)
    # Title is in track_versions list
    assert_equal "Test Memory", version.attribute_value(:title)
  end

  test "version chain is linked correctly" do
    memory = @space.memories.create!(
      account: @account,
      title: "V1",
      content: "Content 1",
      memory_type: "knowledge",
      status: "active"
    )

    memory.update!(content: "Content 2")
    memory.update!(content: "Content 3")

    assert_equal 2, memory.versions.count

    v1 = memory.versions.find_by(version_number: 1)
    v2 = memory.versions.find_by(version_number: 2)

    assert_nil v1.previous_version
    assert_equal v1.id, v2.previous_version_id
  end

  test "restore_version! restores to previous state" do
    memory = @space.memories.create!(
      account: @account,
      title: "Original Title",
      content: "Original content",
      memory_type: "knowledge",
      status: "active"
    )

    memory.update!(content: "Updated content", title: "Updated Title")

    # Version 1 stores: {content: "Original content", title: "Original Title"}
    memory.restore_version!(1, restored_by: @user)

    memory.reload
    assert_equal "Original content", memory.content
    assert_equal "Original Title", memory.title

    # Restore creates a new version
    assert_equal 2, memory.versions.count
  end

  test "whodunnit is recorded from Current.version_whodunnit" do
    Current.version_whodunnit = @user

    memory = @space.memories.create!(
      account: @account,
      title: "Test",
      content: "Content",
      memory_type: "knowledge",
      status: "active"
    )

    memory.update!(content: "Updated")

    version = memory.versions.first
    assert_equal @user, version.whodunnit
  end

  test "metadata is recorded from Current.version_metadata" do
    Current.version_metadata = { change_reason: "Test update" }

    memory = @space.memories.create!(
      account: @account,
      title: "Test",
      content: "Content",
      memory_type: "knowledge",
      status: "active"
    )

    memory.update!(content: "Updated")

    version = memory.versions.first
    assert_equal "Test update", version.metadata["change_reason"]
  end
end
