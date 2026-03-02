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
      roe_type: :consensus,  # Consensus RoE makes all advisors respond
      space: @space
    )

    # Add advisor as participant
    @conversation.conversation_participants.create!(
      advisor: @advisor,
      role: :advisor,
      position: 0
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
    # Mock AI response with new AI system
    token_usage = AI::Model::TokenUsage.new(input: 50, output: 25)
    mock_response = AI::Model::Response.new(
      content: "Here's my response!",
      usage: token_usage
    )

    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    # Create pending message
    message = @conversation.messages.create!(
      account: @account,
      sender: @advisor,
      role: "system",
      content: "Thinking...",
      status: "pending"
    )

    # UsageRecord is created by AI::Client#track_usage on real calls.
    # In tests, AI::ContentGenerator is mocked so AI::Client is never invoked.
    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: message.id
    )

    message.reload
    assert_equal "complete", message.status
    assert_equal "Here's my response!", message.content
    assert_equal "advisor", message.role
  end

  test "message updated after AI response" do
    token_usage = AI::Model::TokenUsage.new(input: 10, output: 5)
    mock_response = AI::Model::Response.new(
      content: "AI generated response",
      usage: token_usage
    )

    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

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
    # Create a conversation in Open RoE with @advisor1
    @conversation.update!(roe_type: :open)

    assert_difference "Message.count", 1 do
      post conversation_messages_path(@conversation), params: {
        message: { content: "Hello without mentions" }
      }
    end

    # Only user message, no advisor message (Open RoE requires mentions)
    assert_equal 1, @conversation.messages.count
  end
end
