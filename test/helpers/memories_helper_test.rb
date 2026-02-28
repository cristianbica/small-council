require "test_helper"

class MemoriesHelperTest < ActionView::TestCase
  include MemoriesHelper

  test "memory_type_badge_class returns badge-primary for summary" do
    assert_equal "badge-primary", memory_type_badge_class("summary")
  end

  test "memory_type_badge_class returns badge-secondary for conversation_summary" do
    assert_equal "badge-secondary", memory_type_badge_class("conversation_summary")
  end

  test "memory_type_badge_class returns badge-accent for conversation_notes" do
    assert_equal "badge-accent", memory_type_badge_class("conversation_notes")
  end

  test "memory_type_badge_class returns badge-info for knowledge" do
    assert_equal "badge-info", memory_type_badge_class("knowledge")
  end

  test "memory_type_badge_class returns badge-ghost for unknown type" do
    assert_equal "badge-ghost", memory_type_badge_class("unknown_type")
  end
end
