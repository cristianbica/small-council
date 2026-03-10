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
end
