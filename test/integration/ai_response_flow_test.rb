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

    # Setup advisor with model
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
    @advisor = @account.advisors.create!(
      name: "Helper Bot",
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
      rules_of_engagement: :round_robin
    )

    sign_in_as(@user)
  end

  test "posting message creates pending advisor message" do
    assert_difference "Message.count", 2 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Hello AI advisor" }
      }
    end

    assert_redirected_to conversation_path(@conversation)

    placeholder = Message.last
    assert_equal @advisor, placeholder.sender
    assert_equal "pending", placeholder.status
    assert_equal "system", placeholder.role
    assert_match(/thinking/, placeholder.content)
  end

  test "background job enqueued on message create" do
    assert_enqueued_with(job: GenerateAdvisorResponseJob) do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Trigger AI response" }
      }
    end
  end

  test "usage record created after AI response" do
    # Mock AI response
    mock_response = {
      content: "Here's my response!",
      input_tokens: 50,
      output_tokens: 25,
      total_tokens: 75
    }
    AIClient.any_instance.stubs(:generate_response).returns(mock_response)

    # Create pending message
    message = @conversation.messages.create!(
      account: @account,
      sender: @advisor,
      role: "system",
      content: "Thinking...",
      status: "pending"
    )

    assert_difference "UsageRecord.count", 1 do
      GenerateAdvisorResponseJob.perform_now(
        advisor_id: @advisor.id,
        conversation_id: @conversation.id,
        message_id: message.id
      )
    end

    usage = UsageRecord.last
    assert_equal @account, usage.account
    assert_equal message, usage.message
    assert_equal "openai", usage.provider
    assert_equal "gpt-4", usage.model
    assert_equal 50, usage.input_tokens
    assert_equal 25, usage.output_tokens
  end

  test "message updated after AI response" do
    mock_response = {
      content: "AI generated response",
      input_tokens: 10,
      output_tokens: 5,
      total_tokens: 15
    }
    AIClient.any_instance.stubs(:generate_response).returns(mock_response)

    message = @conversation.messages.create!(
      account: @account,
      sender: @advisor,
      role: "system",
      content: "Thinking...",
      status: "pending"
    )

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: message.id
    )

    message.reload
    assert_equal "complete", message.status
    assert_equal "AI generated response", message.content
    assert_equal "advisor", message.role
  end

  test "silence mode does not create advisor messages" do
    @conversation.update!(rules_of_engagement: :silent)

    assert_difference "Message.count", 1 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Hello in silent mode" }
      }
    end

    # Only user message, no advisor message
    assert_equal 1, @conversation.messages.count
  end
end
