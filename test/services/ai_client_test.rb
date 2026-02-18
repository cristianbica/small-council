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

  test "call_github_models uses correct endpoint" do
    github_provider = @account.providers.create!(
      name: "GitHub Models",
      provider_type: "github",
      api_key: "github-token"
    )
    github_model = github_provider.llm_models.create!(
      account: @account,
      name: "GPT-4o",
      identifier: "gpt-4o"
    )
    advisor = @account.advisors.create!(
      name: "GitHub Advisor",
      system_prompt: "You are helpful",
      llm_model: github_model
    )

    client = AiClient.new(advisor: advisor, conversation: @conversation, message: @message)

    # Mock the OpenAI client for GitHub endpoint
    mock_response = {
      "choices" => [ { "message" => { "content" => "GitHub response" } } ],
      "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
    }

    mock_client = mock()
    mock_client.expects(:chat).returns(mock_response)
    OpenAI::Client.expects(:new).with(
      access_token: "github-token",
      uri_base: "https://models.inference.ai.azure.com"
    ).returns(mock_client)

    result = client.generate_response

    assert_equal "GitHub response", result[:content]
    assert_equal 10, result[:input_tokens]
    assert_equal 5, result[:output_tokens]
  end

  test "call_anthropic uses messages API" do
    anthropic_provider = @account.providers.create!(
      name: "Anthropic",
      provider_type: "anthropic",
      api_key: "anthropic-key"
    )
    anthropic_model = anthropic_provider.llm_models.create!(
      account: @account,
      name: "Claude",
      identifier: "claude-3-sonnet"
    )
    advisor = @account.advisors.create!(
      name: "Anthropic Advisor",
      system_prompt: "You are Claude",
      llm_model: anthropic_model
    )

    client = AiClient.new(advisor: advisor, conversation: @conversation, message: @message)

    mock_response = {
      "content" => [ { "text" => "Claude response" } ],
      "usage" => { "input_tokens" => 20, "output_tokens" => 10 }
    }

    mock_client = mock()
    mock_client.expects(:messages).returns(mock_response)
    Anthropic::Client.expects(:new).with(access_token: "anthropic-key").returns(mock_client)

    result = client.generate_response

    assert_equal "Claude response", result[:content]
    assert_equal 20, result[:input_tokens]
    assert_equal 10, result[:output_tokens]
    assert_equal 30, result[:total_tokens]
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

  test "build_messages_for_anthropic handles system role as user" do
    # Create a system message in conversation
    system_message = @conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "system",
      content: "System instruction"
    )

    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages_for_anthropic)

    # System messages should be treated as user messages (else branch)
    system_msg = messages.find { |m| m[:content] == "System instruction" }
    assert_equal "user", system_msg[:role]
  end

  test "with_retries succeeds and returns result" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    client.stubs(:sleep).returns(nil)

    result = client.send(:with_retries) do
      "success_result"
    end

    assert_equal "success_result", result
  end

  test "successful OpenAI API call parses response" do
    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    mock_response = {
      "choices" => [ { "message" => { "content" => "API response text" } } ],
      "usage" => { "prompt_tokens" => 15, "completion_tokens" => 8, "total_tokens" => 23 }
    }

    mock_client = mock()
    mock_client.expects(:chat).returns(mock_response)
    OpenAI::Client.expects(:new).returns(mock_client)

    result = client.generate_response

    assert_equal "API response text", result[:content]
    assert_equal 15, result[:input_tokens]
    assert_equal 8, result[:output_tokens]
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
      llm_model: @llm_model
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

    # Should have system prompt + 3 messages (pending message is skipped)
    # pending message is @message which has "Test message"
    assert messages.any? { |m| m[:content] == "User message" && m[:role] == "user" }
    assert messages.any? { |m| m[:content] == "Advisor message" && m[:role] == "assistant" }
    assert messages.any? { |m| m[:content] == "System message" && m[:role] == "user" }
  end

  test "build_messages_for_anthropic covers all role cases" do
    # This test specifically covers lines 127, 128, and 129 in ai_client.rb
    # by creating messages with each possible role

    # User message - covers line 127
    user_msg = @conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "user",
      content: "User content"
    )

    # Create another advisor for advisor message - covers line 128
    other_advisor = @account.advisors.create!(
      name: "Response Advisor",
      system_prompt: "Response prompt",
      llm_model: @llm_model
    )
    advisor_msg = @conversation.messages.create!(
      account: @account,
      sender: other_advisor,
      role: "advisor",
      content: "Advisor content"
    )

    # System message - covers line 129 (else branch)
    system_msg = @conversation.messages.create!(
      account: @account,
      sender: @user,
      role: "system",
      content: "System content"
    )

    client = AiClient.new(advisor: @advisor, conversation: @conversation, message: @message)
    messages = client.send(:build_messages_for_anthropic)

    # Verify each role is correctly mapped
    user_message = messages.find { |m| m[:content] == "User content" }
    advisor_message = messages.find { |m| m[:content] == "Advisor content" }
    system_message = messages.find { |m| m[:content] == "System content" }

    assert_equal "user", user_message[:role], "User role should map to user"
    assert_equal "assistant", advisor_message[:role], "Advisor role should map to assistant"
    assert_equal "user", system_message[:role], "System role should map to user (else branch)"
  end
end
