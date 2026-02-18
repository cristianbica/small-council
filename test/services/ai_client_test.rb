require "test_helper"

class AiClientTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @provider = @account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "test-key")
    @llm_model = @provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    @advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a helpful assistant.",
      llm_model: @llm_model
    )
    @user = @account.users.create!(email: "test@example.com", password: "password123")
    @space = @account.spaces.create!(name: "Test Space")
    @council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
    @conversation = @account.conversations.create!(
      council: @council,
      user: @user,
      title: "Test Conversation"
    )
    @message = @conversation.messages.create!(
      account: @account,
      sender: @advisor,
      role: "system",
      content: "Test message",
      status: "pending"
    )
  end

  test "initialize with advisor, conversation, message" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    assert_equal @advisor, client.advisor
    assert_equal @conversation, client.conversation
    assert_equal @message, client.message
  end

  test "generate_response returns nil without llm_model" do
    # Create advisor without llm_model (skipping validation)
    advisor_without_model = @account.advisors.new(
      name: "Test Advisor No Model",
      system_prompt: "You are a helpful assistant."
    )
    advisor_without_model.save(validate: false)

    client = AiClient.new(advisor: advisor_without_model, conversation: @conversation, message: @message)
    assert_nil client.generate_response
  end

  test "generate_response returns nil with disabled llm_model" do
    @llm_model.update!(enabled: false)
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    assert_nil client.generate_response
  end

  test "build_messages includes system prompt" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages)
    assert_equal "system", messages.first[:role]
    assert_equal @advisor.system_prompt, messages.first[:content]
  end

  test "build_messages includes conversation history" do
    # Add a user message
    user_message = @conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Hello"
    )

    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages)

    # Should have system + user messages
    assert messages.length > 1
    assert_equal "user", messages.last[:role]
    assert_equal "Hello", messages.last[:content]
  end

  test "build_messages skips pending message" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages)

    # Should not include the pending message itself
    assert_not messages.any? { |m| m[:content] == "Test message" }
  end

  test "build_messages_for_anthropic excludes system message" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages_for_anthropic)

    # Anthropic format has no system message in array
    assert_not messages.any? { |m| m[:role] == "system" }
  end

  test "parse_openai_response extracts content and tokens" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    mock_response = {
      "choices" => [ { "message" => { "content" => "Hello!" } } ],
      "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
    }

    result = client.send(:parse_openai_response, mock_response)

    assert_equal "Hello!", result[:content]
    assert_equal 10, result[:input_tokens]
    assert_equal 5, result[:output_tokens]
    assert_equal 15, result[:total_tokens]
  end

  test "parse_anthropic_response extracts content and tokens" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    mock_response = {
      "content" => [ { "text" => "Hi there!" } ],
      "usage" => { "input_tokens" => 8, "output_tokens" => 4 }
    }

    result = client.send(:parse_anthropic_response, mock_response)

    assert_equal "Hi there!", result[:content]
    assert_equal 8, result[:input_tokens]
    assert_equal 4, result[:output_tokens]
    assert_equal 12, result[:total_tokens]
  end

  test "raises error for unsupported provider" do
    @provider.update!(provider_type: "gemini")
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    assert_raises(AiClient::Error) do
      client.generate_response
    end
  end

  test "raises ApiError when API call fails" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    # Mock OpenAI client to raise error
    mock_client = mock()
    mock_client.stubs(:chat).raises(StandardError, "Connection timeout")
    OpenAI::Client.stubs(:new).returns(mock_client)

    assert_raises(AiClient::ApiError) do
      client.generate_response
    end
  end

  test "with_retries retries on transient errors" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    call_count = 0
    client.stubs(:sleep).returns(nil)
    assert_raises(StandardError) do
      client.send(:with_retries) do
        call_count += 1
        raise StandardError, "Transient error"
      end
    end

    # Should retry MAX_RETRIES times (2) plus initial attempt = 3
    assert_equal 3, call_count
  end

  test "with_retries succeeds on retry" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    call_count = 0
    client.stubs(:sleep).returns(nil)
    result = client.send(:with_retries) do
      call_count += 1
      if call_count < 2
        raise StandardError, "Transient error"
      end
      "success"
    end

    assert_equal "success", result
    assert_equal 2, call_count
  end

  test "log_error logs error with advisor id" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    error = StandardError.new("Test error")
    error.set_backtrace([ "line1", "line2" ])

    # Just verify it doesn't raise
    assert_nothing_raised do
      client.send(:log_error, error)
    end
  end

  test "build_messages handles advisor role" do
    # Create an advisor message in conversation
    other_advisor = @account.advisors.create!(
      name: "Other Advisor",
      system_prompt: "Other prompt",
      llm_model: @llm_model
    )
    advisor_message = @conversation.messages.create!(
      account: @account,
      sender: other_advisor,
      role: "advisor",
      content: "Advisor message"
    )

    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages)

    # Find the advisor message
    advisor_msg = messages.find { |m| m[:content] == "Advisor message" }
    assert_equal "assistant", advisor_msg[:role]
  end

  test "build_messages_for_anthropic handles advisor role" do
    # Create an advisor message in conversation
    other_advisor = @account.advisors.create!(
      name: "Other Advisor",
      system_prompt: "Other prompt",
      llm_model: @llm_model
    )
    advisor_message = @conversation.messages.create!(
      account: @account,
      sender: other_advisor,
      role: "advisor",
      content: "Advisor message"
    )

    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages_for_anthropic)

    # Find the advisor message
    advisor_msg = messages.find { |m| m[:content] == "Advisor message" }
    assert_equal "assistant", advisor_msg[:role]
  end
end
