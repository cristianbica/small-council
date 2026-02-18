require "test_helper"

class GenerateAdvisorResponseJobTest < ActiveJob::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @provider = @account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "key")
    @llm_model = @provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    @advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are helpful.",
      llm_model: @llm_model
    )
    @user = @account.users.create!(email: "test@example.com", password: "password123")
    @space = @account.spaces.create!(name: "Test Space")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    @conversation = @account.conversations.create!(
      council: @council,
      user: @user,
      title: "Test"
    )
    @message = @conversation.messages.create!(
      account: @account,
      sender: @advisor,
      role: "system",
      content: "Thinking...",
      status: "pending"
    )
  end

  test "enqueues job" do
    assert_enqueued_with(job: GenerateAdvisorResponseJob) do
      GenerateAdvisorResponseJob.perform_later(
        advisor_id: @advisor.id,
        conversation_id: @conversation.id,
        message_id: @message.id
      )
    end
  end

  test "skips processing if message not pending" do
    @message.update!(status: "complete")

    # Job should return early without calling AI
    AiClient.expects(:new).never

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )
  end

  test "skips processing if advisor not found" do
    GenerateAdvisorResponseJob.perform_now(
      advisor_id: 99999,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    # Message should remain unchanged
    @message.reload
    assert_equal "pending", @message.status
  end

  test "skips processing if conversation not found" do
    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: 99999,
      message_id: @message.id
    )

    @message.reload
    assert_equal "pending", @message.status
  end

  test "skips processing if message not found" do
    # Job should return early without error when message not found
    assert_nothing_raised do
      GenerateAdvisorResponseJob.perform_now(
        advisor_id: @advisor.id,
        conversation_id: @conversation.id,
        message_id: 99999
      )
    end
  end

  test "creates usage record after successful generation" do
    mock_response = {
      content: "Hello! I'm here to help!",
      input_tokens: 100,
      output_tokens: 50,
      total_tokens: 150
    }

    AiClient.any_instance.stubs(:generate_response).returns(mock_response)

    assert_difference "UsageRecord.count", 1 do
      GenerateAdvisorResponseJob.perform_now(
        advisor_id: @advisor.id,
        conversation_id: @conversation.id,
        message_id: @message.id
      )
    end

    usage = UsageRecord.last
    assert_equal @account, usage.account
    assert_equal @message, usage.message
    assert_equal "openai", usage.provider
    assert_equal "gpt-4", usage.model
    assert_equal 100, usage.input_tokens
    assert_equal 50, usage.output_tokens
    assert usage.cost_cents > 0
  end

  test "marks message as complete on success" do
    mock_response = {
      content: "Here's my response!",
      input_tokens: 50,
      output_tokens: 25,
      total_tokens: 75
    }

    AiClient.any_instance.stubs(:generate_response).returns(mock_response)

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    @message.reload
    assert @message.complete?
    assert_equal "Here's my response!", @message.content
    assert_equal "advisor", @message.role
  end

  test "marks message as error on API failure" do
    AiClient.any_instance.stubs(:generate_response).raises(AiClient::ApiError, "API Error")

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    @message.reload
    assert @message.error?
    assert_match(/API Error/, @message.content)
  end

  test "marks message as error on empty response" do
    AiClient.any_instance.stubs(:generate_response).returns({ content: nil })

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    @message.reload
    assert @message.error?
    assert_match(/Empty response/, @message.content)
  end

  test "clears tenant after job" do
    AiClient.any_instance.stubs(:generate_response).returns({
      content: "Hello!",
      input_tokens: 10,
      output_tokens: 5,
      total_tokens: 15
    })

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    assert_nil ActsAsTenant.current_tenant
  end
end
