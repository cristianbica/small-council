# frozen_string_literal: true

require "test_helper"

# Example controller test demonstrating how to mock AI::Client
# in existing controller tests. This serves as a pattern for migration.
class AIClientControllerMockExampleTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:one)
    set_tenant(@account)
    @user = users(:one)
    @space = @account.spaces.first || @account.spaces.create!(name: "Test Space")

    # Create necessary records
    @provider = @account.providers.create!(
      name: "Test Provider",
      provider_type: "openai",
      api_key: "test-key"
    )
    @llm_model = @provider.llm_models.create!(
      account: @account,
      name: "GPT-4",
      identifier: "gpt-4",
      enabled: true
    )
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
      title: "Test Conversation",
      space: @space
    )
    sign_in_as(@user)
  end

  test "example: mocking AI::Client in controller tests" do
    # This test demonstrates the pattern for mocking AI::Client in controllers.
    # In a real scenario, a controller might use AI::Client like this:
    #
    #   client = AI::Client.new(
    #     model: @advisor.llm_model,
    #     tools: [AI::Tools::Internal::QueryMemoriesTool.new],
    #     system_prompt: @advisor.system_prompt
    #   )
    #   response = client.chat(
    #     messages: messages,
    #     context: { space: @space, conversation: @conversation }
    #   )
    #   render json: { content: response.content }
    #
    # To test this without hitting the real API:

    # 1. Create a mock response
    mock_response = AI::Model::Response.new(
      content: "This is a mocked AI response",
      usage: AI::Model::TokenUsage.new(input: 50, output: 25)
    )

    # 2. Create a mock client
    mock_client = mock("AI::Client")
    mock_client.stubs(:chat).returns(mock_response)

    # 3. Mock the Client constructor to return your mock
    AI::Client.stubs(:new).returns(mock_client)

    # 4. Now when the controller calls AI::Client.new, it gets your mock
    #    and .chat returns the mock response without hitting the API

    # Example usage verification:
    client = AI::Client.new(
      model: @advisor.llm_model,
      tools: [],
      system_prompt: "test"
    )
    response = client.chat(
      messages: [ { role: "user", content: "Hello" } ],
      context: { space: @space }
    )

    assert_equal "This is a mocked AI response", response.content
    assert_equal 50, response.usage.input_tokens
    assert_equal 75, response.usage.total_tokens
  end

  test "example: mocking with specific parameter expectations" do
    # More specific mocking to verify correct parameters are passed

    mock_client = mock("AI::Client")

    # Expect specific parameters
    mock_client.expects(:chat)
               .with(
                 messages: [ { role: "user", content: "Hello" } ],
                 context: { space: @space, conversation: @conversation }
               )
               .returns(
                 AI::Model::Response.new(content: "Mocked response")
               )

    AI::Client.stubs(:new).returns(mock_client)

    # This would be called by the controller
    client = AI::Client.new(model: @advisor.llm_model, tools: [])
    response = client.chat(
      messages: [ { role: "user", content: "Hello" } ],
      context: { space: @space, conversation: @conversation }
    )

    assert_equal "Mocked response", response.content
  end

  test "example: mocking tool responses" do
    # When testing tool execution, you can mock the tool responses

    mock_tool_result = {
      success: true,
      memories: [
        { id: 1, title: "Memory 1", preview: "Content..." }
      ]
    }

    # Create a real tool instance and stub its execute method
    real_tool = AI::Tools::Internal::QueryMemoriesTool.new
    real_tool.stubs(:execute).returns(mock_tool_result)

    # Mock the tool class to return our stubbed instance
    AI::Tools::Internal::QueryMemoriesTool.stubs(:new).returns(real_tool)

    # Verify mock is used
    tool = AI::Tools::Internal::QueryMemoriesTool.new
    result = tool.execute({ query: "test" }, { space: @space })

    assert_equal mock_tool_result, result
  end

  test "example: testing error handling with mocked client" do
    # Test how controller handles AI::Client errors

    mock_client = mock("AI::Client")
    mock_client.stubs(:chat).raises(AI::Client::RateLimitError, "Rate limited")
    AI::Client.stubs(:new).returns(mock_client)

    # Controller would catch this and render appropriate error
    error = assert_raises(AI::Client::RateLimitError) do
      client = AI::Client.new(model: @advisor.llm_model, tools: [])
      client.chat(messages: [ { role: "user", content: "Hello" } ], context: {})
    end

    assert_match(/Rate limited/, error.message)
  end

  test "example: verifying no actual API calls are made" do
    # Ensure no real API calls happen during testing

    # Mock RubyLLM entirely to ensure it's never called
    RubyLLM.stubs(:context).never

    # Use mocked client
    mock_response = AI::Model::Response.new(content: "Mock")
    AI::Client.stubs(:new).returns(stub(chat: mock_response))

    # Test passes if RubyLLM.context is never called
    client = AI::Client.new(model: @advisor.llm_model, tools: [])
    response = client.chat(messages: [], context: {})
    assert_equal "Mock", response.content
  end
end
