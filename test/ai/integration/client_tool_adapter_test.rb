# frozen_string_literal: true

require "test_helper"

module AI
  # Integration test: Client → RubyLLMToolAdapter → QueryMemoriesTool
  # Tests the full flow with mocked RubyLLM to ensure context flows correctly
  class ClientToolAdapterIntegrationTest < ActiveSupport::TestCase
    setup do
      @account = accounts(:one)
      set_tenant(@account)

      # Create provider and model since there are no fixtures
      @provider = @account.providers.create!(
        name: "OpenAI",
        provider_type: "openai",
        api_key: "test-key"
      )
      @llm_model = @provider.llm_models.create!(
        account: @account,
        name: "GPT-4",
        identifier: "gpt-4",
        enabled: true
      )

      @space = @account.spaces.first || @account.spaces.create!(name: "Test Space")
      @user = users(:one)

      # Create a council and conversation
      council = @account.councils.create!(name: "Test Council", user: @user, space: @space)
      @conversation = @account.conversations.create!(
        council: council,
        user: @user,
        title: "Test Conversation"
      )

      # Create some test memories through the account (which sets both account_id and space_id)
      @memory1 = Memory.create!(
        account: @account,
        space: @space,
        title: "Project Goals",
        content: "Our main objectives for Q1",
        memory_type: "knowledge",
        status: "active"
      )
      @memory2 = Memory.create!(
        account: @account,
        space: @space,
        title: "Meeting Notes",
        content: "Notes from the kickoff meeting",
        memory_type: "knowledge",
        status: "active"
      )
    end

    test "full flow: adapter passes context to tool" do
      tool = AI::Tools::Internal::QueryMemoriesTool.new
      adapter = tool.to_ruby_llm_tool

      # Set context as Client would do
      context = {
        space: @space,
        conversation: @conversation,
        user: @user,
        account: @account
      }
      adapter.context = context

      # Get the RubyLLM tool instance
      ruby_llm_tool = adapter.to_ruby_llm_tool

      # Execute through RubyLLM tool (as RubyLLM would)
      result_json = ruby_llm_tool.execute(query: "Project")
      result = JSON.parse(result_json, symbolize_names: true)

      # Verify tool executed with context
      assert result[:success]
      assert result[:memories].length >= 1
      assert result[:memories].any? { |m| m[:title] == "Project Goals" }
    end

    test "context isolation: multiple adapters share tool but not context" do
      tool = AI::Tools::Internal::QueryMemoriesTool.new

      # Create two adapters for the same tool
      adapter1 = tool.to_ruby_llm_tool
      adapter2 = tool.to_ruby_llm_tool

      # Set different contexts
      space2 = @account.spaces.create!(name: "Other Space")
      Memory.create!(
        account: @account,
        space: space2,
        title: "Other Memory",
        content: "Content in other space",
        memory_type: "knowledge",
        status: "active"
      )

      adapter1.context = { space: @space }
      adapter2.context = { space: space2 }

      # Get RubyLLM tool instances
      ruby_llm_tool1 = adapter1.to_ruby_llm_tool
      ruby_llm_tool2 = adapter2.to_ruby_llm_tool

      # Execute both
      result1 = JSON.parse(ruby_llm_tool1.execute(query: "Project"), symbolize_names: true)
      result2 = JSON.parse(ruby_llm_tool2.execute(query: "Other"), symbolize_names: true)

      # Each adapter should see only its own space
      assert result1[:memories].any? { |m| m[:title] == "Project Goals" }
      assert_not result1[:memories].any? { |m| m[:title] == "Other Memory" }

      assert_not result2[:memories].any? { |m| m[:title] == "Project Goals" }
      assert result2[:memories].any? { |m| m[:title] == "Other Memory" }
    end

    test "adapter handles errors gracefully" do
      tool = AI::Tools::Internal::QueryMemoriesTool.new
      adapter = tool.to_ruby_llm_tool

      # Missing context should result in error response, not exception
      ruby_llm_tool = adapter.to_ruby_llm_tool
      result_json = ruby_llm_tool.execute(query: "test")
      result = JSON.parse(result_json, symbolize_names: true)

      # Adapter catches errors and returns JSON
      assert_not result[:success]
      assert result[:error].present?
    end

    test "token usage is tracked when context provided" do
      mock_response = Struct.new(:content, :input_tokens, :output_tokens, :model_id, :tool_calls).new(
        "Response", 100, 50, "gpt-4", nil
      )

      mock_chat = Struct.new(:response).new(mock_response)
      def mock_chat.with_instructions(*); self; end
      def mock_chat.with_temperature(*); self; end
      def mock_chat.add_message(*); self; end
      def mock_chat.complete; response; end

      mock_context = Struct.new(:chat_result).new(mock_chat)
      def mock_context.chat(**args); chat_result; end

      client = AI::Client.new(model: @llm_model)

      RubyLLM.stubs(:context).yields(stub(:openai_api_key= => nil, :openai_organization_id= => nil)).returns(mock_context)

      assert_difference "UsageRecord.count", 1 do
        client.chat(
          messages: [ { role: "user", content: "Hello" } ],
          context: {
            space: @space,
            conversation: @conversation,
            account: @account
          }
        )
      end

      record = UsageRecord.last
      assert_equal 100, record.input_tokens
      assert_equal 50, record.output_tokens
      assert_equal @llm_model.identifier, record.model
    end
  end
end
