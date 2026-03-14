# frozen_string_literal: true

require "test_helper"

class MessagesHelperTest < ActionView::TestCase
  include MessagesHelper

  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @conversation = conversations(:one)
    @conversation.ensure_scribe_present!
    @scribe = @conversation.scribe_advisor
  end

  test "message_display_content returns normal content for chat messages" do
    chat_message = @conversation.messages.create!(
      account: @account,
      sender: @conversation.user,
      role: "user",
      content: "Hello world",
      status: "complete",
      message_type: "chat"
    )

    assert_equal "Hello world", message_display_content(chat_message)
  end

  test "message_display_content returns Compacting ... for pending compaction messages" do
    compaction_message = @conversation.messages.create!(
      account: @account,
      sender: @scribe,
      role: "advisor",
      content: "...",
      status: "pending",
      message_type: "compaction"
    )

    assert_equal "Compacting ...", message_display_content(compaction_message)
  end

  test "message_display_content returns Compacting ... for responding compaction messages" do
    compaction_message = @conversation.messages.create!(
      account: @account,
      sender: @scribe,
      role: "advisor",
      content: "...",
      status: "responding",
      message_type: "compaction"
    )

    assert_equal "Compacting ...", message_display_content(compaction_message)
  end

  test "message_display_content returns Content compacted for complete compaction messages" do
    compaction_message = @conversation.messages.create!(
      account: @account,
      sender: @scribe,
      role: "advisor",
      content: "Compacted summary of conversation...",
      status: "complete",
      message_type: "compaction"
    )

    assert_equal "Content compacted", message_display_content(compaction_message)
  end

  test "message_display_content returns actual content for errored compaction messages" do
    compaction_message = @conversation.messages.create!(
      account: @account,
      sender: @scribe,
      role: "advisor",
      content: "Error: Failed to compact",
      status: "error",
      message_type: "compaction"
    )

    assert_equal "Error: Failed to compact", message_display_content(compaction_message)
  end
end
