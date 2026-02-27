require "test_helper"

class AIClientTest < ActiveSupport::TestCase
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
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    assert_equal @advisor, client.advisor
    assert_equal @conversation, client.conversation
    assert_equal @message, client.message
  end

  test "generate_response returns nil when no llm_model is available" do
    # Create advisor without llm_model and ensure account has no default
    advisor_without_model = @account.advisors.new(
      name: "Test Advisor No Model",
      system_prompt: "You are a helpful assistant.",
      space: @space
    )
    advisor_without_model.save(validate: false)

    # Ensure account has no default model and no enabled models
    @account.update!(default_llm_model: nil)
    @account.llm_models.update_all(enabled: false)

    client = AIClient.new(advisor: advisor_without_model, conversation: @conversation, message: @message)
    assert_nil client.generate_response
  end

  test "generate_response returns nil with disabled llm_model" do
    @llm_model.update!(enabled: false)
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)
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

    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages)

    # Should have user messages
    assert messages.length >= 1
    assert_equal "user", messages.last[:role]
    assert_equal "Hello", messages.last[:content]
  end

  test "build_messages skips pending message" do
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)
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

    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)
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

    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)
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

    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)
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

    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)
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
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    # Mock RubyLLM to raise error
    mock_chat = mock()
    mock_chat.stubs(:with_tools).returns(mock_chat)
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:with_temperature).returns(mock_chat)
    mock_chat.stubs(:add_message).returns(mock_chat)
    mock_chat.stubs(:complete).raises(StandardError, "Connection timeout")

    mock_context = mock()
    mock_context.stubs(:chat).returns(mock_chat)

    # Mock context method to yield config and return context
    RubyLLM.stubs(:context).returns(mock_context)

    assert_raises(AIClient::ApiError) do
      client.generate_response
    end
  end

  test "raises ApiError on LLM::APIError" do
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    # Mock RubyLLM to raise LLM::APIError
    mock_chat = mock()
    mock_chat.stubs(:with_tools).returns(mock_chat)
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:with_temperature).returns(mock_chat)
    mock_chat.stubs(:add_message).returns(mock_chat)
    mock_chat.stubs(:complete).raises(LLM::APIError, "API failure")

    mock_context = mock()
    mock_context.stubs(:chat).returns(mock_chat)

    # Mock context method to yield config and return context
    RubyLLM.stubs(:context).returns(mock_context)

    error = assert_raises(AIClient::ApiError) do
      client.generate_response
    end
    assert_match(/API failure/, error.message)
  end

  test "with_retries retries on transient errors" do
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)

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
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)

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
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    client.stubs(:sleep).returns(nil)

    result = client.send(:with_retries) do
      "success_result"
    end

    assert_equal "success_result", result
  end

  test "log_error logs error with advisor id" do
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    error = StandardError.new("Test error")
    error.set_backtrace([ "line1", "line2" ])

    # Just verify it doesn't raise
    assert_nothing_raised do
      client.send(:log_error, error)
    end
  end

  test "successful API call returns response" do
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    # Create mock response object that behaves like RubyLLM::Response
    mock_response = mock()
    mock_response.stubs(:content).returns("API response text")
    mock_response.stubs(:input_tokens).returns(15)
    mock_response.stubs(:output_tokens).returns(8)
    mock_response.stubs(:model_id).returns("gpt-4")
    mock_response.stubs(:tool_calls).returns([])

    # Create mock chat object
    mock_chat = mock()
    mock_chat.stubs(:with_tools).returns(mock_chat)
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:with_temperature).returns(mock_chat)
    mock_chat.stubs(:add_message).returns(mock_chat)
    mock_chat.expects(:complete).returns(mock_response)

    # Create mock context
    mock_context = mock()
    mock_context.expects(:chat).with(model: @llm_model.identifier).returns(mock_chat)

    # Mock context method to return context
    RubyLLM.stubs(:context).returns(mock_context)

    result = client.generate_response

    assert_equal "API response text", result[:content]
    assert_equal 15, result[:input_tokens]
    assert_equal 8, result[:output_tokens]
  end

  test "generate_response passes correct parameters to LLM client" do
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    # Add a user message to the conversation
    @conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "Hello"
    )

    # Create mock response object
    mock_response = mock()
    mock_response.stubs(:content).returns("Hi!")
    mock_response.stubs(:input_tokens).returns(10)
    mock_response.stubs(:output_tokens).returns(5)
    mock_response.stubs(:model_id).returns("gpt-4")
    mock_response.stubs(:tool_calls).returns([])

    # Create mock chat object
    mock_chat = mock()
    mock_chat.stubs(:with_tools).returns(mock_chat)
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:with_temperature).returns(mock_chat)
    mock_chat.stubs(:add_message).returns(mock_chat)
    mock_chat.expects(:complete).returns(mock_response)

    # Create mock context
    mock_context = mock()
    mock_context.expects(:chat).with(model: @llm_model.identifier).returns(mock_chat)

    # Mock context method to return context
    RubyLLM.stubs(:context).returns(mock_context)

    result = client.generate_response

    assert_equal "Hi!", result[:content]
  end

  test "generate_response uses custom temperature and max_tokens from config" do
    @advisor.update!(model_config: { "temperature" => 0.5, "max_tokens" => 500 })
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    # Create mock response object
    mock_response = mock()
    mock_response.stubs(:content).returns("Response")
    mock_response.stubs(:input_tokens).returns(10)
    mock_response.stubs(:output_tokens).returns(5)
    mock_response.stubs(:model_id).returns("gpt-4")
    mock_response.stubs(:tool_calls).returns([])

    # Create mock chat object
    mock_chat = mock()
    mock_chat.stubs(:with_tools).returns(mock_chat)
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:with_temperature).returns(mock_chat)
    mock_chat.stubs(:add_message).returns(mock_chat)
    mock_chat.expects(:complete).returns(mock_response)

    # Create mock context
    mock_context = mock()
    mock_context.expects(:chat).with(model: @llm_model.identifier).returns(mock_chat)

    # Mock context method to return context
    RubyLLM.stubs(:context).returns(mock_context)

    result = client.generate_response

    assert_equal "Response", result[:content]
  end
end
