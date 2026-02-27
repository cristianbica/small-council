require "test_helper"

class AdvisorToolAccessTest < ActiveSupport::TestCase
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
    @other_advisor = @account.advisors.create!(
      name: "Other Advisor",
      system_prompt: "You are another advisor.",
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

  test "advisors have access to 4 tools via ScribeToolExecutor" do
    advisor_tools = ScribeToolExecutor.available_tools(for_scribe: false)

    assert_equal 4, advisor_tools.count
    assert_includes advisor_tools, AdvisorTools::QueryMemoriesTool
    assert_includes advisor_tools, AdvisorTools::QueryConversationsTool
    assert_includes advisor_tools, AdvisorTools::ReadConversationTool
    assert_includes advisor_tools, AdvisorTools::AskAdvisorTool
  end

  test "scribe has access to all 8 tools via ScribeToolExecutor" do
    all_tools = ScribeToolExecutor.available_tools(for_scribe: true)

    assert_equal 8, all_tools.count
    # Scribe tools (4)
    assert_includes all_tools, ScribeTools::FinishConversationTool
    assert_includes all_tools, ScribeTools::CreateMemoryTool
    assert_includes all_tools, ScribeTools::QueryMemoriesTool
    assert_includes all_tools, ScribeTools::BrowseWebTool
    # Advisor tools (4)
    assert_includes all_tools, AdvisorTools::QueryMemoriesTool
    assert_includes all_tools, AdvisorTools::QueryConversationsTool
    assert_includes all_tools, AdvisorTools::ReadConversationTool
    assert_includes all_tools, AdvisorTools::AskAdvisorTool
  end

  test "advisor can execute ask_advisor tool" do
    context = ToolExecutionContext.new(
      conversation: @conversation,
      space: @space,
      advisor: @advisor,
      user: @user
    )

    result = ScribeToolExecutor.execute(
      tool_name: "ask_advisor",
      params: {
        "advisor_name" => @other_advisor.name,
        "question" => "What do you think about this approach?"
      },
      context: context,
      for_scribe: false
    )

    assert result[:success], "Expected ask_advisor to succeed: #{result[:message]}"
    assert_match(/Asked #{@other_advisor.name}/, result[:message])
    assert result[:data][:pending_message_id].present?
  end

  test "advisor ask_advisor tool prevents asking self" do
    context = ToolExecutionContext.new(
      conversation: @conversation,
      space: @space,
      advisor: @advisor,
      user: @user
    )

    result = ScribeToolExecutor.execute(
      tool_name: "ask_advisor",
      params: {
        "advisor_name" => @advisor.name,
        "question" => "What do I think?"
      },
      context: context,
      for_scribe: false
    )

    assert_not result[:success]
    assert_match(/cannot ask yourself/, result[:message])
  end

  test "advisor ask_advisor tool handles missing advisor" do
    context = ToolExecutionContext.new(
      conversation: @conversation,
      space: @space,
      advisor: @advisor,
      user: @user
    )

    result = ScribeToolExecutor.execute(
      tool_name: "ask_advisor",
      params: {
        "advisor_name" => "Nonexistent Advisor",
        "question" => "What do you think?"
      },
      context: context,
      for_scribe: false
    )

    assert_not result[:success]
    assert_match(/not found/, result[:message])
    assert result[:data][:available_advisors].present?
  end

  test "RubyLLM advisor tools are defined" do
    # Verify the RubyLLM tool wrappers exist
    assert defined?(RubyLLMTools::AdvisorQueryMemoriesTool)
    assert defined?(RubyLLMTools::AdvisorQueryConversationsTool)
    assert defined?(RubyLLMTools::AdvisorReadConversationTool)
    assert defined?(RubyLLMTools::AdvisorAskAdvisorTool)

    # Verify they inherit from RubyLLM::Tool
    assert RubyLLMTools::AdvisorQueryMemoriesTool < RubyLLM::Tool
    assert RubyLLMTools::AdvisorQueryConversationsTool < RubyLLM::Tool
    assert RubyLLMTools::AdvisorReadConversationTool < RubyLLM::Tool
    assert RubyLLMTools::AdvisorAskAdvisorTool < RubyLLM::Tool
  end

  test "RubyLLM advisor tools have correct metadata" do
    tool = RubyLLMTools::AdvisorAskAdvisorTool.new
    # RubyLLM tool names include module prefix
    assert tool.name.include?("ask_advisor")
    assert tool.description.present?
    assert tool.description.include?("ONLY way to communicate")

    tool = RubyLLMTools::AdvisorQueryMemoriesTool.new
    assert tool.name.include?("query_memories")
    assert tool.description.present?
  end

  test "AIClient sets advisor tool context in thread" do
    client = AIClient.new(advisor: @advisor, conversation: @conversation, message: @message)

    # Create mock response
    mock_response = mock()
    mock_response.stubs(:content).returns("Test response")
    mock_response.stubs(:input_tokens).returns(10)
    mock_response.stubs(:output_tokens).returns(5)
    mock_response.stubs(:model_id).returns("gpt-4")
    mock_response.stubs(:tool_calls).returns([])

    # Create mock chat
    mock_chat = mock()
    mock_chat.stubs(:with_tools).returns(mock_chat)
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:with_temperature).returns(mock_chat)
    mock_chat.stubs(:add_message).returns(mock_chat)
    mock_chat.stubs(:complete).returns(mock_response)

    # Create mock context
    mock_context = mock()
    mock_context.stubs(:chat).returns(mock_chat)

    RubyLLM.stubs(:context).returns(mock_context)

    # Before calling, context should be nil
    assert_nil Thread.current[:advisor_tool_context]

    # Call generate_response
    client.generate_response

    # After calling, context should be cleaned up
    assert_nil Thread.current[:advisor_tool_context]
  end
end
