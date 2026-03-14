require "test_helper"

class AiResponseFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @account = accounts(:one)
    set_tenant(@account)

    # Setup provider and model
    @provider = @account.providers.create!(
      name: "OpenAI Test",
      provider_type: "openai",
      api_key: "test-key"
    )
    @llm_model = @provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4"
    )

    # Setup advisor with model - using canonical name format (lowercase with hyphens)
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
    @advisor = @account.advisors.create!(
      name: "helper-bot",
      system_prompt: "You are a helpful assistant.",
      llm_model: @llm_model,
      space: @space
    )
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    @council.advisors << @advisor

    @conversation = @account.conversations.create!(
      council: @council,
      user: @user,
      title: "AI Test Conversation",
      roe_type: :consensus,  # Consensus RoE makes all advisors respond
      space: @space
    )

    # Add advisor as participant
    @conversation.conversation_participants.create!(
      advisor: @advisor,
      role: :advisor,
      position: 0
    )

    # Ensure scribe is present (needed for runtime)
    @conversation.ensure_scribe_present!

    sign_in_as(@user)
  end

  test "posting message creates pending advisor message" do
    assert_difference "Message.count", 2 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Hello @helper-bot" }
      }
    end

    assert_redirected_to conversation_path(@conversation)

    placeholder = Message.last
    assert_equal @advisor, placeholder.sender
    assert_equal "pending", placeholder.status
    assert_equal "advisor", placeholder.role
    assert_equal "...", placeholder.content
  end

  test "background job enqueued on message create" do
    assert_enqueued_with(job: AIRunnerJob) do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Trigger @helper-bot response" }
      }
    end
  end

  test "open mode without mentions with multiple advisors creates only user message" do
    # After ensure_scribe_present!, conversation has 2 advisors (helper-bot + scribe)
    @conversation.update!(roe_type: :open)

    # In open mode without mentions, when there are multiple advisors, no responses are triggered
    assert_difference "Message.count", 1 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Hello without mentions" }
      }
    end
  end
end
