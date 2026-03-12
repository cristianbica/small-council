require "test_helper"

class RecordVersionTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @space = spaces(:one)
    @user = users(:one)
    set_tenant(@account)

    @memory = @space.memories.create!(
      account: @account,
      title: "Test Memory",
      content: "Test content",
      memory_type: "knowledge",
      status: "active"
    )
  end

  test "validations" do
    version = RecordVersion.new(
      versionable: @memory,
      version_number: 1,
      object_data: { title: "Test" },
      metadata: {}
    )
    assert version.valid?

    # version_number must be > 0
    version.version_number = 0
    assert_not version.valid?
    assert_includes version.errors[:version_number], "must be greater than 0"
  end

  test "uniqueness of version_number per versionable" do
    RecordVersion.create!(
      versionable: @memory,
      version_number: 1,
      object_data: {},
      metadata: {}
    )

    duplicate = RecordVersion.new(
      versionable: @memory,
      version_number: 1,
      object_data: {},
      metadata: {}
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:version_number], "has already been taken"
  end

  test "scopes" do
    v1 = RecordVersion.create!(
      versionable: @memory,
      version_number: 1,
      object_data: {},
      metadata: {},
      created_at: 2.days.ago
    )

    v2 = RecordVersion.create!(
      versionable: @memory,
      version_number: 2,
      previous_version: v1,
      object_data: {},
      metadata: {},
      created_at: 1.day.ago
    )

    # ordered scope (descending)
    ordered = @memory.versions.ordered.to_a
    assert_equal [ 2, 1 ], ordered.map(&:version_number)

    # chronological scope (ascending)
    chronological = @memory.versions.chronological.to_a
    assert_equal [ 1, 2 ], chronological.map(&:version_number)
  end

  test "attribute_value retrieves value from object_data" do
    version = RecordVersion.create!(
      versionable: @memory,
      version_number: 1,
      object_data: { "title" => "Stored Title", "content" => "Stored Content" },
      metadata: {}
    )

    assert_equal "Stored Title", version.attribute_value(:title)
    assert_equal "Stored Content", version.attribute_value("content")
    assert_nil version.attribute_value(:nonexistent)
  end

  test "to_model_attributes returns indifferent access hash" do
    version = RecordVersion.create!(
      versionable: @memory,
      version_number: 1,
      object_data: { "title" => "Test", "content" => "Body" },
      metadata: {}
    )

    attrs = version.to_model_attributes
    assert_equal "Test", attrs[:title]
    assert_equal "Test", attrs["title"]
  end

  test "whodunnit_display returns email for User" do
    version = RecordVersion.create!(
      versionable: @memory,
      version_number: 1,
      whodunnit: @user,
      object_data: {},
      metadata: {}
    )

    assert_equal @user.email, version.whodunnit_display
  end

  test "whodunnit_display returns name for Advisor" do
    provider = @account.providers.create!(name: "Test Provider", provider_type: "openai", api_key: "key")
    model = provider.llm_models.create!(account: @account, name: "GPT", identifier: "gpt")
    advisor = @account.advisors.create!(
      name: "test-advisor",
      system_prompt: "You are a test",
      llm_model: model,
      space: @space
    )

    version = RecordVersion.create!(
      versionable: @memory,
      version_number: 1,
      whodunnit: advisor,
      object_data: {},
      metadata: {}
    )

    assert_equal "test-advisor", version.whodunnit_display
  end

  test "whodunnit_display returns Unknown when nil" do
    version = RecordVersion.create!(
      versionable: @memory,
      version_number: 1,
      whodunnit: nil,
      object_data: {},
      metadata: {}
    )

    assert_equal "Unknown", version.whodunnit_display
  end

  test "polymorphic associations" do
    version = RecordVersion.create!(
      versionable: @memory,
      version_number: 1,
      object_data: {},
      metadata: {}
    )

    assert_equal "Memory", version.versionable_type
    assert_equal @memory.id, version.versionable_id
  end

  test "previous_version association" do
    v1 = RecordVersion.create!(
      versionable: @memory,
      version_number: 1,
      object_data: {},
      metadata: {}
    )

    v2 = RecordVersion.create!(
      versionable: @memory,
      version_number: 2,
      previous_version: v1,
      object_data: {},
      metadata: {}
    )

    assert_equal v1.id, v2.previous_version_id
    assert_equal v1, v2.previous_version
  end

  test "next_version association" do
    v1 = RecordVersion.create!(
      versionable: @memory,
      version_number: 1,
      object_data: {},
      metadata: {}
    )

    v2 = RecordVersion.create!(
      versionable: @memory,
      version_number: 2,
      previous_version: v1,
      object_data: {},
      metadata: {}
    )

    assert_equal v2, v1.next_version
  end
end
