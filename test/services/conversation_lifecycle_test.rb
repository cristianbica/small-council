require "test_helper"

class ConversationLifecycleTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:one)
    @user = users(:one)
    set_tenant(@account)

    @space = @account.spaces.first || @account.spaces.create!(name: "General")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)

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

    @advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a test advisor",
      llm_model: @llm_model
    )
    @council.advisors << @advisor

    @conversation = @account.conversations.create!(
      council: @council,
      user: @user,
      title: "Test Conversation",
      rules_of_engagement: :round_robin
    )

    @lifecycle = ConversationLifecycle.new(@conversation)
  end

  test "user_posted_message creates pending messages and enqueues jobs" do
    user_message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Hello"
    )

    assert_difference "Message.where(status: :pending).count", 1 do
      assert_enqueued_with(job: GenerateAdvisorResponseJob) do
        @lifecycle.user_posted_message(user_message)
      end
    end

    pending = Message.where(status: :pending).last
    assert_equal @advisor, pending.sender
    assert_equal "system", pending.role
    assert_match(/thinking/, pending.content)
  end

  test "user_posted_message returns early if message not persisted" do
    user_message = @conversation.messages.new(
      sender: @user,
      role: "user",
      content: "Hello"
    )
    # Don't save - so persisted? returns false

    assert_no_difference "Message.where(status: :pending).count" do
      @lifecycle.user_posted_message(user_message)
    end
  end

  test "advisor_responded updates message and broadcasts" do
    pending_message = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "system",
      content: "[Test Advisor] is thinking...",
      status: "pending"
    )

    @lifecycle.advisor_responded(@advisor, "Here's my response", pending_message)

    pending_message.reload
    assert_equal "Here's my response", pending_message.content
    assert_equal "advisor", pending_message.role
    assert_equal "complete", pending_message.status
  end

  test "advisor_responded returns early if message not pending" do
    completed_message = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "advisor",
      content: "Already complete",
      status: "complete"
    )

    @lifecycle.advisor_responded(@advisor, "New response", completed_message)

    completed_message.reload
    assert_equal "Already complete", completed_message.content
    assert_equal "complete", completed_message.status
  end

  test "advisor_responded updates round_robin state" do
    @conversation.update!(rules_of_engagement: :round_robin)
    lifecycle = ConversationLifecycle.new(@conversation)

    pending_message = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "system",
      content: "Thinking...",
      status: "pending"
    )

    lifecycle.advisor_responded(@advisor, "Response", pending_message)

    assert_equal @advisor.id.to_s, @conversation.reload.last_advisor_id.to_s
  end

  test "handles error in advisor_responded" do
    pending_message = @account.messages.create!(
      conversation: @conversation,
      sender: @advisor,
      role: "system",
      content: "Thinking...",
      status: "pending"
    )

    # Simulate an error by making update! raise an error
    pending_message.stubs(:update!).raises(StandardError, "Test error")

    assert_raises(StandardError) do
      @lifecycle.advisor_responded(@advisor, "Response", pending_message)
    end
  end

  test "user_posted_message handles empty responders" do
    # Set to silent mode so no advisors respond
    @conversation.update!(rules_of_engagement: :silent)
    lifecycle = ConversationLifecycle.new(@conversation)

    user_message = @account.messages.create!(
      conversation: @conversation,
      sender: @user,
      role: "user",
      content: "Hello"
    )

    assert_no_difference "Message.where(status: :pending).count" do
      lifecycle.user_posted_message(user_message)
    end
  end
end
