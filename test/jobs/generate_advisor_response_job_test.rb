require "test_helper"

class GenerateAdvisorResponseJobTest < ActiveJob::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @provider = @account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "key")
    @llm_model = @provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    @user = @account.users.create!(email: "test@example.com", password: "password123")
    @space = @account.spaces.create!(name: "Test Space")
    @advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are helpful.",
      llm_model: @llm_model,
      space: @space
    )
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
    AI::ContentGenerator.expects(:new).never

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
    # Create mock response with token usage
    token_usage = AI::Model::TokenUsage.new(
      input: 100,
      output: 50
    )
    mock_response = AI::Model::Response.new(
      content: "Hello! I'm here to help!",
      usage: token_usage
    )

    # Create a mock generator
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

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
    token_usage = AI::Model::TokenUsage.new(
      input: 50,
      output: 25
    )
    mock_response = AI::Model::Response.new(
      content: "Here's my response!",
      usage: token_usage
    )

    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

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
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).raises(
      AI::Client::APIError, "API Error"
    )
    AI::ContentGenerator.expects(:new).returns(mock_generator)

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
    mock_response = AI::Model::Response.new(content: "")
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

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
    token_usage = AI::Model::TokenUsage.new(
      input: 10,
      output: 5
    )
    mock_response = AI::Model::Response.new(
      content: "Hello!",
      usage: token_usage
    )

    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    assert_nil ActsAsTenant.current_tenant
  end

  test "marks message as error on unexpected error" do
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).raises(
      StandardError, "Unexpected failure"
    )
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    @message.reload
    assert @message.error?
    assert_match(/Unexpected error/, @message.content)
  end

  test "calculates cost for openrouter provider" do
    openrouter_provider = @account.providers.create!(
      name: "OpenRouter",
      provider_type: "openrouter",
      api_key: "openrouter-key"
    )
    openrouter_model = openrouter_provider.llm_models.create!(
      account: @account,
      name: "Claude via OpenRouter",
      identifier: "anthropic/claude-3-sonnet"
    )
    advisor = @account.advisors.create!(
      name: "OpenRouter Advisor",
      system_prompt: "You are helpful",
      llm_model: openrouter_model,
      space: @space
    )
    message = @conversation.messages.create!(
      account: @account,
      sender: advisor,
      role: "system",
      content: "Thinking...",
      status: "pending"
    )

    token_usage = AI::Model::TokenUsage.new(
      input: 1000,
      output: 500
    )
    mock_response = AI::Model::Response.new(
      content: "Hello from Claude via OpenRouter!",
      usage: token_usage
    )

    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    assert_difference "UsageRecord.count", 1 do
      GenerateAdvisorResponseJob.perform_now(
        advisor_id: advisor.id,
        conversation_id: @conversation.id,
        message_id: message.id
      )
    end

    usage = UsageRecord.last
    assert_equal "openrouter", usage.provider
    # Using default rates: $0.03/1K input, $0.06/1K output
    # Cost = (1000 * 0.03/1000) + (500 * 0.06/1000) = 0.03 + 0.03 = 0.06 dollars = 6 cents
    assert_equal 6, usage.cost_cents
  end

  test "logs error on unexpected exception" do
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).raises(
      StandardError, "Something went wrong"
    )
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    # Just verify job completes without raising and logs the error
    assert_nothing_raised do
      GenerateAdvisorResponseJob.perform_now(
        advisor_id: @advisor.id,
        conversation_id: @conversation.id,
        message_id: @message.id
      )
    end

    @message.reload
    assert @message.error?
  end

  test "skips processing if message is cancelled" do
    @message.update!(status: "cancelled")

    # Job should return early without calling AI
    AI::ContentGenerator.expects(:new).never

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    # Message should remain cancelled (not changed to complete or error)
    @message.reload
    assert @message.cancelled?
  end

  test "marks message as error on NoModelError" do
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).raises(
      AI::ContentGenerator::NoModelError, "No model configured"
    )
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    @message.reload
    assert @message.error?
    assert_match(/No AI Model/, @message.content)
  end

  # is_scribe_followup branch tests
  test "calls generate_scribe_followup when is_scribe_followup is true and advisor is scribe" do
    # Create a scribe advisor
    scribe = @account.advisors.create!(
      name: "Scribe", system_prompt: "You are the scribe",
      llm_model: @llm_model, space: @space, is_scribe: true
    )
    @council.council_advisors.create!(advisor: scribe, position: 0)
    message = @conversation.messages.create!(
      account: @account, sender: scribe, role: "system",
      content: "Thinking...", status: "pending"
    )

    token_usage = AI::Model::TokenUsage.new(input: 10, output: 5)
    mock_response = AI::Model::Response.new(content: "Scribe summary", usage: token_usage)
    mock_generator = mock("generator")
    mock_generator.expects(:generate_scribe_followup).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: scribe.id,
      conversation_id: @conversation.id,
      message_id: message.id,
      is_scribe_followup: true
    )

    message.reload
    assert message.complete?
    assert_equal "Scribe summary", message.content
  end

  test "calls generate_advisor_response for scribe when is_scribe_followup is false" do
    scribe = @account.advisors.create!(
      name: "Scribe", system_prompt: "You are the scribe",
      llm_model: @llm_model, space: @space, is_scribe: true
    )
    @council.council_advisors.create!(advisor: scribe, position: 0)
    message = @conversation.messages.create!(
      account: @account, sender: scribe, role: "system",
      content: "Thinking...", status: "pending"
    )

    token_usage = AI::Model::TokenUsage.new(input: 10, output: 5)
    mock_response = AI::Model::Response.new(content: "Scribe response", usage: token_usage)
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: scribe.id,
      conversation_id: @conversation.id,
      message_id: message.id,
      is_scribe_followup: false
    )

    message.reload
    assert message.complete?
  end

  # Space resolution tests
  test "resolves space from council for council_meeting conversation" do
    # @conversation is a council_meeting (belongs to @council which belongs to @space)
    assert @conversation.council_meeting?
    token_usage = AI::Model::TokenUsage.new(input: 10, output: 5)
    mock_response = AI::Model::Response.new(content: "Hello", usage: token_usage)
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    # Job should complete without error - space was resolved from council
    @message.reload
    assert @message.complete?
  end

  test "resolves space from advisor for adhoc conversation" do
    # Create adhoc conversation (no council)
    adhoc_conv = @account.conversations.create!(
      user: @user, title: "Adhoc", conversation_type: "adhoc"
    )
    adhoc_msg = adhoc_conv.messages.create!(
      account: @account, sender: @advisor, role: "system",
      content: "Thinking...", status: "pending"
    )
    adhoc_conv.conversation_participants.create!(
      advisor: @advisor, role: "advisor"
    )

    token_usage = AI::Model::TokenUsage.new(input: 10, output: 5)
    mock_response = AI::Model::Response.new(content: "Adhoc reply", usage: token_usage)
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: adhoc_conv.id,
      message_id: adhoc_msg.id
    )

    adhoc_msg.reload
    assert adhoc_msg.complete?
  end

  # Cost calculation tests
  # NOTE: calculate_cost_from_tokens has a dead code path for "anthropic" provider_type,
  # which cannot be created (Provider enum only allows openai/openrouter). Tested via default rates.
  test "calculates cost using default rates for openrouter provider" do
    openrouter_provider = @account.providers.create!(
      name: "Job Cost OR",
      provider_type: "openrouter",
      api_key: "or-key"
    )
    or_model = openrouter_provider.llm_models.create!(
      account: @account, name: "Claude via OR", identifier: "anthropic/claude-3"
    )
    advisor = @account.advisors.create!(
      name: "OR Advisor", system_prompt: "You are helpful",
      llm_model: or_model, space: @space
    )
    message = @conversation.messages.create!(
      account: @account, sender: advisor, role: "system",
      content: "Thinking...", status: "pending"
    )

    # Default rates: $0.03/1K input, $0.06/1K output
    # 1000 input + 1000 output = 0.03 + 0.06 = 0.09 dollars = 9 cents
    token_usage = AI::Model::TokenUsage.new(input: 1000, output: 1000)
    mock_response = AI::Model::Response.new(content: "Hello from OR", usage: token_usage)
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    assert_difference "UsageRecord.count", 1 do
      GenerateAdvisorResponseJob.perform_now(
        advisor_id: advisor.id,
        conversation_id: @conversation.id,
        message_id: message.id
      )
    end

    usage = UsageRecord.last
    assert_equal "openrouter", usage.provider
    # (1000 * 0.03/1000) + (1000 * 0.06/1000) = 0.03 + 0.06 = 0.09 dollars = 9 cents
    assert_equal 9, usage.cost_cents
  end

  test "skips usage record creation when advisor has no llm model" do
    # Advisor with no llm_model and no account default → effective_llm_model returns nil
    no_model_advisor = @account.advisors.create!(
      name: "No Model Advisor",
      system_prompt: "You have no model",
      llm_model: nil,
      space: @space
    )
    message = @conversation.messages.create!(
      account: @account, sender: no_model_advisor, role: "system",
      content: "Thinking...", status: "pending"
    )

    token_usage = AI::Model::TokenUsage.new(input: 10, output: 5)
    mock_response = AI::Model::Response.new(content: "Response without model", usage: token_usage)
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    # Stub effective_llm_model to return nil
    no_model_advisor.stubs(:effective_llm_model).returns(nil)
    Advisor.stubs(:find_by).with(id: no_model_advisor.id).returns(no_model_advisor)

    assert_no_difference "UsageRecord.count" do
      GenerateAdvisorResponseJob.perform_now(
        advisor_id: no_model_advisor.id,
        conversation_id: @conversation.id,
        message_id: message.id
      )
    end

    message.reload
    assert message.complete?
  end

  test "resolves space from first participant when advisor has no space in adhoc conversation" do
    # Create an advisor with no space
    spaceless_advisor = @account.advisors.create!(
      name: "Spaceless Advisor",
      system_prompt: "I have no space",
      llm_model: @llm_model,
      space: nil
    )
    adhoc_conv = @account.conversations.create!(
      user: @user, title: "Adhoc Spaceless", conversation_type: "adhoc"
    )
    adhoc_msg = adhoc_conv.messages.create!(
      account: @account, sender: spaceless_advisor, role: "system",
      content: "Thinking...", status: "pending"
    )
    # Add @advisor (who has a space) as a participant
    adhoc_conv.conversation_participants.create!(
      advisor: @advisor, role: "advisor"
    )

    token_usage = AI::Model::TokenUsage.new(input: 10, output: 5)
    mock_response = AI::Model::Response.new(content: "Reply", usage: token_usage)
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: spaceless_advisor.id,
      conversation_id: adhoc_conv.id,
      message_id: adhoc_msg.id
    )

    adhoc_msg.reload
    assert adhoc_msg.complete?
  end

  test "handle_error calls lifecycle advisor_response_error when lifecycle is non-nil" do
    # Make lifecycle.advisor_responded raise so lifecycle is set but error occurs after
    lifecycle_mock = mock("lifecycle")
    lifecycle_mock.expects(:advisor_responded).raises(StandardError, "lifecycle error")
    lifecycle_mock.expects(:advisor_response_error).once
    ConversationLifecycle.expects(:new).returns(lifecycle_mock)

    token_usage = AI::Model::TokenUsage.new(input: 10, output: 5)
    mock_response = AI::Model::Response.new(content: "Response", usage: token_usage)
    mock_generator = mock("generator")
    mock_generator.expects(:generate_advisor_response).returns(mock_response)
    AI::ContentGenerator.expects(:new).returns(mock_generator)

    GenerateAdvisorResponseJob.perform_now(
      advisor_id: @advisor.id,
      conversation_id: @conversation.id,
      message_id: @message.id
    )

    @message.reload
    assert @message.error?
  end
end
