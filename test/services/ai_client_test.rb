require "test_helper"

class AiClientTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @provider = @account.providers.create!(name: "OpenAI", provider_type: "openai", api_key: "test-key")
    @llm_model = @provider.llm_models.create!(account: @account, name: "GPT-4", identifier: "gpt-4")
    @user = @account.users.create!(email: "test@example.com", password: "password123")
    @space = @account.spaces.create!(name: "Test Space")
    @advisor = @account.advisors.create!(
      name: "Test Advisor",
      system_prompt: "You are a helpful assistant.",
      llm_model: @llm_model,
      space: @space
    )
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
      system_prompt: "You are a helpful assistant.",
      space: @space
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

    # Should have user messages
    assert messages.length >= 1
    assert_equal "user", messages.last[:role]
    assert_equal "Hello", messages.last[:content]
  end

  test "build_messages skips pending message" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages)

    # Should not include the pending message itself
    assert_not messages.any? { |m| m[:content] == "Test message" }
  end

  test "build_messages handles advisor role" do
    # Create an advisor message in conversation
    other_advisor = @account.advisors.create!(
      name: "Other Advisor",
      system_prompt: "Other prompt",
      llm_model: @llm_model,
      space: @space
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

  test "build_messages handles system role as user" do
    # Create a system message in conversation
    system_message = @conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "system",
      content: "System instruction"
    )

    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages)

    # System messages should be treated as user messages (else branch)
    system_msg = messages.find { |m| m[:content] == "System instruction" }
    assert_equal "user", system_msg[:role]
  end

  test "build_messages includes various message types" do
    # Create messages with different roles
    user_msg = @conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "User message"
    )

    # Create advisor
    other_advisor = @account.advisors.create!(
      name: "Other Advisor",
      system_prompt: "Other prompt",
      llm_model: @llm_model,
      space: @space
    )
    advisor_msg = @conversation.messages.create!(
      account: @account,
      sender: other_advisor,
      role: "advisor",
      content: "Advisor message"
    )

    # Create system message
    system_msg = @conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "system",
      content: "System message"
    )

    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages)

    # pending message is @message which has "Test message"
    assert messages.any? { |m| m[:content] == "User message" && m[:role] == "user" }
    assert messages.any? { |m| m[:content] == "Advisor message" && m[:role] == "assistant" }
    assert messages.any? { |m| m[:content] == "System message" && m[:role] == "user" }
  end

  test "build_messages covers all role cases" do
    # This test specifically covers all role mappings

    # User message
    user_msg = @conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "User content"
    )

    # Create another advisor for advisor message
    other_advisor = @account.advisors.create!(
      name: "Response Advisor",
      system_prompt: "Response prompt",
      llm_model: @llm_model,
      space: @space
    )
    advisor_msg = @conversation.messages.create!(
      account: @account,
      sender: other_advisor,
      role: "advisor",
      content: "Advisor content"
    )

    # System message - covers else branch
    system_msg = @conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "system",
      content: "System content"
    )

    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages)

    # Verify each role is correctly mapped
    user_message = messages.find { |m| m[:content] == "User content" }
    advisor_message = messages.find { |m| m[:content] == "Advisor content" }
    system_message = messages.find { |m| m[:content] == "System content" }

    assert_equal "user", user_message[:role], "User role should map to user"
    assert_equal "assistant", advisor_message[:role], "Advisor role should map to assistant"
    assert_equal "user", system_message[:role], "System role should map to user (else branch)"
  end

  test "raises ApiError when API call fails" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    # Mock LLM::Client to raise error via the llm_model.api
    mock_api = mock()
    mock_api.stubs(:chat).raises(StandardError, "Connection timeout")
    @llm_model.stubs(:api).returns(mock_api)

    assert_raises(AiClient::ApiError) do
      client.generate_response
    end
  end

  test "raises ApiError on LLM::APIError" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    # Mock LLM::Client to raise LLM::APIError
    mock_api = mock()
    mock_api.stubs(:chat).raises(LLM::APIError, "API failure")
    @llm_model.stubs(:api).returns(mock_api)

    error = assert_raises(AiClient::ApiError) do
      client.generate_response
    end
    assert_match(/API failure/, error.message)
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

  test "with_retries succeeds and returns result" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    client.stubs(:sleep).returns(nil)

    result = client.send(:with_retries) do
      "success_result"
    end

    assert_equal "success_result", result
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

  test "successful API call returns response" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    mock_response = {
      content: "API response text",
      input_tokens: 15,
      output_tokens: 8,
      total_tokens: 23,
      model: "gpt-4",
      provider: "openai"
    }

    mock_api = mock()
    mock_api.expects(:chat).returns(mock_response)
    @llm_model.stubs(:api).returns(mock_api)

    result = client.generate_response

    assert_equal "API response text", result[:content]
    assert_equal 15, result[:input_tokens]
    assert_equal 8, result[:output_tokens]
  end

  test "generate_response passes correct parameters to LLM client" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    # Add a user message to the conversation
    @conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Hello"
    )

    expected_messages = [
      { role: "user", content: "Hello" }
    ]

    mock_api = mock()
    # System prompt now includes enhanced council and expertise context
    # Verify the call is made with correct parameters
    mock_api.expects(:chat).with(
      expected_messages,
      has_entries(
        system_prompt: includes(@advisor.system_prompt),
        temperature: 0.7,
        max_tokens: 1000
      )
    ).returns({ content: "Hi!", input_tokens: 10, output_tokens: 5, total_tokens: 15 })
    @llm_model.stubs(:api).returns(mock_api)

    result = client.generate_response

    assert_equal "Hi!", result[:content]
  end

  test "generate_response uses custom temperature and max_tokens from config" do
    @advisor.update!(model_config: { "temperature" => 0.5, "max_tokens" => 500 })
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    mock_api = mock()
    # System prompt now includes enhanced council and expertise context
    # Verify the call is made with correct temperature and max_tokens
    mock_api.expects(:chat).with(
      anything,
      has_entries(
        system_prompt: includes(@advisor.system_prompt),
        temperature: 0.5,
        max_tokens: 500
      )
    ).returns({ content: "Response", input_tokens: 10, output_tokens: 5, total_tokens: 15 })
    @llm_model.stubs(:api).returns(mock_api)

    client.generate_response
  end
end
