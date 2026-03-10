require "test_helper"

class GenerateConversationTitleJobTest < ActiveJob::TestCase
  def setup
    @account = accounts(:one)
    set_tenant(@account)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")

    @provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )
    @llm_model = @provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )
  end

  test "updates title for first user message on adhoc conversation" do
    conversation = @account.conversations.create!(
      title: "New conversation",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.ensure_scribe_present!

    first_message = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Can you help me design a launch plan?"
    )

    result = AI::Result.new
    result.content = "Launch Plan"
    AI.expects(:generate_text).returns(result)

    GenerateConversationTitleJob.perform_now(conversation.id, first_message.id)

    assert_equal "Launch Plan", conversation.reload.title
  end

  test "does not update title when locked" do
    conversation = @account.conversations.create!(
      title: "Manual title",
      title_locked: true,
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.ensure_scribe_present!

    first_message = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Please review this architecture"
    )

    AI.expects(:generate_text).never

    GenerateConversationTitleJob.perform_now(conversation.id, first_message.id)

    assert_equal "Manual title", conversation.reload.title
  end

  test "does not update title for non-first user message" do
    conversation = @account.conversations.create!(
      title: "New conversation",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    conversation.ensure_scribe_present!

    conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "First message"
    )
    second_message = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Second message"
    )

    AI.expects(:generate_text).never

    GenerateConversationTitleJob.perform_now(conversation.id, second_message.id)

    assert_equal "New conversation", conversation.reload.title
  end

  test "returns early when conversation is missing" do
    AI.expects(:generate_text).never

    assert_nothing_raised do
      GenerateConversationTitleJob.perform_now(-1, -1)
    end
  end

  test "returns early when conversation is not adhoc" do
    conversation = @account.conversations.create!(
      title: "Council Conversation",
      user: @user,
      council: @account.councils.first,
      conversation_type: :council_meeting,
      space: @space
    )
    first_message = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "First"
    )

    AI.expects(:generate_text).never
    GenerateConversationTitleJob.perform_now(conversation.id, first_message.id)
  end

  test "returns early when target message is missing or not a user message" do
    conversation = @account.conversations.create!(
      title: "New conversation",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )

    system_message = conversation.messages.create!(
      account: @account,
      sender: advisors(:one),
      role: "advisor",
      content: "System"
    )

    AI.expects(:generate_text).never
    GenerateConversationTitleJob.perform_now(conversation.id, system_message.id)
    GenerateConversationTitleJob.perform_now(conversation.id, -1)
  end

  test "does not update when generated title is blank" do
    conversation = @account.conversations.create!(
      title: "Keep title",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    first_message = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Suggest title"
    )

    result = AI::Result.new
    result.content = "   "
    AI.expects(:generate_text).returns(result)

    GenerateConversationTitleJob.perform_now(conversation.id, first_message.id)

    assert_equal "Keep title", conversation.reload.title
  end

  test "normalizes generated title with squish and max length" do
    conversation = @account.conversations.create!(
      title: "Old",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    first_message = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Need title"
    )

    long_title = ("  One   two  " + ("x" * 300))
    result = AI::Result.new
    result.content = long_title
    AI.expects(:generate_text).returns(result)

    GenerateConversationTitleJob.perform_now(conversation.id, first_message.id)

    assert_equal 255, conversation.reload.title.length
    assert_includes conversation.title, "One two"
  end

  test "rescues AI resolution and client errors" do
    conversation = @account.conversations.create!(
      title: "Old",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    first_message = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Need title"
    )

    Rails.logger.expects(:warn).twice

    AI.expects(:generate_text).raises(AI::ResolutionError.new("missing prompt"))
    GenerateConversationTitleJob.perform_now(conversation.id, first_message.id)

    AI.expects(:generate_text).raises(AI::Client::Error.new("provider fail"))
    GenerateConversationTitleJob.perform_now(conversation.id, first_message.id)
  end

  test "rescues unexpected errors" do
    conversation = @account.conversations.create!(
      title: "Old",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    first_message = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Need title"
    )

    Rails.logger.expects(:error).once
    AI.expects(:generate_text).raises(StandardError.new("boom"))

    GenerateConversationTitleJob.perform_now(conversation.id, first_message.id)
  end

  test "always clears tenant in ensure even on early return" do
    ActsAsTenant.current_tenant = @account

    GenerateConversationTitleJob.perform_now(-1, -1)

    assert_nil ActsAsTenant.current_tenant
  end

  test "passes expected prompt inputs to AI generator" do
    conversation = @account.conversations.create!(
      title: "Old",
      user: @user,
      conversation_type: :adhoc,
      space: @space
    )
    first_message = conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Help me draft a product announcement"
    )

    result = AI::Result.new
    result.content = "Product Announcement Draft"

    AI.expects(:generate_text).with(
      has_entries(
        prompt: "tasks/conversation_title",
        description: "Help me draft a product announcement",
        space: conversation.space,
        account: @account,
        async: false
      )
    ).returns(result)

    GenerateConversationTitleJob.perform_now(conversation.id, first_message.id)

    assert_equal "Product Announcement Draft", conversation.reload.title
  end
end
