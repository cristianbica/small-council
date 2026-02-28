require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper

  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "Helper Test Space")

    @council = @account.councils.create!(name: "Helper Council", user: @user, space: @space)
    @conversation = @account.conversations.create!(
      council: @council, user: @user, title: "Helper Conversation"
    )

    # Mock Current.user via a stub session
    @mock_session = stub(user: @user)
    Current.session = @mock_session
  end

  teardown do
    Current.session = nil
  end

  def set_current_user(user)
    Current.session = stub(user: user)
  end

  # status_badge_class tests
  test "status_badge_class returns badge-success for active" do
    @conversation.update_column(:status, "active")
    assert_equal "badge-success", status_badge_class(@conversation)
  end

  test "status_badge_class returns badge-warning for concluding" do
    @conversation.update_column(:status, "concluding")
    assert_equal "badge-warning", status_badge_class(@conversation)
  end

  test "status_badge_class returns badge-primary for resolved" do
    @conversation.update_column(:status, "resolved")
    assert_equal "badge-primary", status_badge_class(@conversation)
  end

  test "status_badge_class returns badge-ghost for archived" do
    @conversation.update_column(:status, "archived")
    assert_equal "badge-ghost", status_badge_class(@conversation)
  end

  test "status_badge_class returns badge-ghost for unknown status" do
    @conversation.stubs(:status).returns("unknown")
    assert_equal "badge-ghost", status_badge_class(@conversation)
  end

  # can_finish_conversation? tests
  test "can_finish_conversation? returns true when user is conversation starter and conversation is active" do
    set_current_user(@user)
    @conversation.update_column(:status, "active")
    assert can_finish_conversation?(@conversation)
  end

  test "can_finish_conversation? returns true when user is council creator and conversation is active" do
    other_user = @account.users.create!(email: "council_creator@example.com", password: "password123")
    council = @account.councils.create!(name: "Creator Council", user: other_user, space: @space)
    conversation = @account.conversations.create!(
      council: council, user: @user, title: "Creator Conv"
    )
    set_current_user(other_user)
    assert can_finish_conversation?(conversation)
  end

  test "can_finish_conversation? returns false when user is neither starter nor council creator" do
    other_user = @account.users.create!(email: "other_user@example.com", password: "password123")
    set_current_user(other_user)
    @conversation.update_column(:status, "active")
    assert_not can_finish_conversation?(@conversation)
  end

  test "can_finish_conversation? returns false when conversation is not active" do
    set_current_user(@user)
    @conversation.update_column(:status, "resolved")
    assert_not can_finish_conversation?(@conversation)
  end

  # can_delete_conversation? tests
  test "can_delete_conversation? returns true when user is conversation starter" do
    set_current_user(@user)
    assert can_delete_conversation?(@conversation)
  end

  test "can_delete_conversation? returns true when user is council creator" do
    other_user = @account.users.create!(email: "del_council@example.com", password: "password123")
    council = @account.councils.create!(name: "Del Council", user: other_user, space: @space)
    conversation = @account.conversations.create!(
      council: council, user: @user, title: "Del Conv"
    )
    set_current_user(other_user)
    assert can_delete_conversation?(conversation)
  end

  test "can_delete_conversation? returns false when user is neither" do
    other_user = @account.users.create!(email: "neither_user@example.com", password: "password123")
    set_current_user(other_user)
    assert_not can_delete_conversation?(@conversation)
  end
end
