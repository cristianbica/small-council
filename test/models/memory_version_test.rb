require "test_helper"

class MemoryVersionTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @space = spaces(:one)
    @user = users(:one)
    set_tenant(@account)

    @memory = @space.memories.create!(
      account: @account,
      title: "Versioned Memory",
      content: "Original content",
      memory_type: "knowledge",
      status: "active"
    )
    # after_create callback creates version 1 automatically
    @version = @memory.versions.first
  end

  # created_by_display tests

  test "created_by_display returns Unknown when created_by is nil" do
    @version.update_column(:created_by_type, nil)
    @version.update_column(:created_by_id, nil)
    @version.reload
    assert_equal "Unknown", @version.created_by_display
  end

  test "created_by_display returns user email when created_by is a User" do
    @version.update!(created_by: @user)
    assert_equal @user.email, @version.created_by_display
  end

  test "created_by_display returns advisor name when created_by is an Advisor" do
    provider = @account.providers.create!(name: "MV Provider", provider_type: "openai", api_key: "key")
    model = provider.llm_models.create!(account: @account, name: "GPT", identifier: "gpt-mv")
    advisor = @account.advisors.create!(
      name: "Advisor Bob", system_prompt: "You are Bob",
      llm_model: model, space: @space
    )
    @version.update!(created_by: advisor)
    assert_equal "Advisor Bob", @version.created_by_display
  end

  test "created_by_display falls through to to_s for other types" do
    # Force an unexpected type by stubbing created_by with a mock
    other_obj = Object.new
    def other_obj.to_s = "FallbackString"
    @version.stubs(:created_by).returns(other_obj)
    # Neither User nor Advisor — hits else branch
    result = @version.created_by_display
    assert_equal "FallbackString", result
  end

  # restore_to_memory! tests

  test "restore_to_memory! without reason creates restore version without colon suffix" do
    # Restore with no reason — reason.present? is false
    original_count = @memory.versions.count
    @version.restore_to_memory!(nil, nil)

    new_version = @memory.versions.order(version_number: :asc).last
    assert_match(/Restored from version #{@version.version_number}$/, new_version.change_reason)
    assert_equal original_count + 1, @memory.versions.count
  end

  test "restore_to_memory! with reason appends reason to change_reason" do
    # Restore with a reason — reason.present? is true
    @version.restore_to_memory!(nil, "fixing error")

    new_version = @memory.versions.order(version_number: :asc).last
    assert_match(/Restored from version #{@version.version_number}: fixing error/, new_version.change_reason)
  end

  test "restore_to_memory! updates memory content" do
    @memory.update!(content: "Updated content after creation")
    @version.restore_to_memory!(@user, nil)

    @memory.reload
    assert_equal @version.content, @memory.content
  end
end
