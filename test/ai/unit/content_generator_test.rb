# frozen_string_literal: true

require "test_helper"

module AI
  class ContentGeneratorTest < ActiveSupport::TestCase
    setup do
      @account = accounts(:one)
      set_tenant(@account)

      @provider = @account.providers.create!(
        name: "OpenAI",
        provider_type: "openai",
        api_key: "test-key"
      )
      @llm_model = @provider.llm_models.create!(
        account: @account,
        name: "GPT-4",
        identifier: "gpt-4",
        enabled: true,
        free: true
      )

      @space = @account.spaces.first || @account.spaces.create!(name: "Test Space")
      @user = users(:one)

      @council = @account.councils.create!(
        name: "Test Council",
        user: @user,
        space: @space
      )
      @conversation = @account.conversations.create!(
        council: @council,
        user: @user,
        title: "Test Conversation",
        space: @space
      )

      @advisor = @space.advisors.create!(
        account: @account,
        name: "Test Advisor",
        system_prompt: "You are a helpful advisor.",
        llm_model: @llm_model
      )
    end

    # Initialization Tests

    test "initializes with default client" do
      generator = ContentGenerator.new
      assert_nil generator.instance_variable_get(:@client)
    end

    test "initializes with provided client" do
      mock_client = stub("client")
      generator = ContentGenerator.new(client: mock_client)
      assert_equal mock_client, generator.instance_variable_get(:@client)
    end

    test "initializes with cache" do
      mock_cache = stub("cache")
      generator = ContentGenerator.new(cache: mock_cache)
      assert_equal mock_cache, generator.instance_variable_get(:@cache)
    end

    # generate_advisor_response Tests

    test "generate_advisor_response calls client with proper context" do
      mock_response = AI::Model::Response.new(content: "Test response")
      mock_client = stub("client")
      captured_messages = nil
      mock_client.stubs(:chat).with do |payload|
        captured_messages = payload[:messages]
        true
      end.returns(mock_response)

      generator = ContentGenerator.new(client: mock_client)

      # Create messages for the conversation
      @account.messages.create!(
        conversation: @conversation,
        sender: @user,
        role: "user",
        content: "Hello"
      )
      @account.messages.create!(
        conversation: @conversation,
        sender: @advisor,
        role: "advisor",
        content: "Welcome"
      )
      @account.messages.create!(
        conversation: @conversation,
        sender: @advisor,
        role: "system",
        content: "[Test Advisor] is thinking...",
        status: "pending",
        parent_message: @conversation.messages.first
      )

      response = generator.generate_advisor_response(
        advisor: @advisor,
        conversation: @conversation
      )

      assert_equal "Test response", response.content
      assert_equal "user", captured_messages.first[:sender_name]
      assert_includes captured_messages.map { |message| message[:sender_name] }, "Test Advisor"
      refute_includes captured_messages.map { |message| message[:content] }, "[Test Advisor] is thinking..."
    end

    test "generate_advisor_response raises NoModelError when no model available" do
      # Create advisor without LLM model
      advisor_without_model = @space.advisors.create!(
        account: @account,
        name: "No Model Advisor",
        system_prompt: "You are an advisor with no model.",
        llm_model: nil
      )

      # Remove all models from account (advisor falls back to account.llm_models.enabled.first)
      @account.update!(default_llm_model: nil)
      @account.llm_models.update_all(enabled: false)

      generator = ContentGenerator.new

      assert_raises(ContentGenerator::NoModelError) do
        generator.generate_advisor_response(
          advisor: advisor_without_model,
          conversation: @conversation
        )
      end
    end

    # generate_conversation_summary Tests

    test "generate_conversation_summary returns summary text" do
      mock_response = AI::Model::Response.new(content: "This is a summary.")
      mock_client = stub("client")
      mock_client.stubs(:complete).returns(mock_response)

      generator = ContentGenerator.new(client: mock_client)

      # Create messages
      @account.messages.create!(
        conversation: @conversation,
        sender: @user,
        role: "user",
        content: "Message 1"
      )
      @account.messages.create!(
        conversation: @conversation,
        sender: @advisor,
        role: "advisor",
        content: "Response 1"
      )

      summary = generator.generate_conversation_summary(
        conversation: @conversation,
        style: :brief
      )

      assert_equal "This is a summary.", summary
    end

    test "generate_conversation_summary supports different styles" do
      mock_client = stub("client")
      mock_client.stubs(:complete).returns(AI::Model::Response.new(content: "Summary"))

      generator = ContentGenerator.new(client: mock_client)

      # Create a message
      @account.messages.create!(
        conversation: @conversation,
        sender: @user,
        role: "user",
        content: "Hello"
      )

      [ :brief, :detailed, :bullet_points ].each do |style|
        result = generator.generate_conversation_summary(
          conversation: @conversation,
          style: style
        )
        assert_equal "Summary", result
      end
    end

    # generate_memory_content Tests

    test "generate_memory_content returns generated content" do
      mock_response = AI::Model::Response.new(content: "Generated memory content.")
      mock_client = stub("client")
      mock_client.stubs(:complete).returns(mock_response)

      generator = ContentGenerator.new(client: mock_client)

      content = generator.generate_memory_content(
        prompt: "Create a summary of project status",
        context: { account: @account }
      )

      assert_equal "Generated memory content.", content
    end

    test "generate_memory_content raises GenerationError without account" do
      generator = ContentGenerator.new

      assert_raises(ContentGenerator::GenerationError) do
        generator.generate_memory_content(
          prompt: "Create a summary",
          context: {} # Missing account
        )
      end
    end

    # generate_advisor_profile Tests

    test "generate_advisor_profile returns parsed JSON" do
      json_response = {
        name: "Expert Advisor",
        short_description: "A helpful expert advisor.",
        system_prompt: "You are an expert advisor."
      }.to_json

      mock_response = AI::Model::Response.new(content: json_response)
      mock_client = stub("client")
      mock_client.stubs(:complete).returns(mock_response)

      generator = ContentGenerator.new(client: mock_client)

      result = generator.generate_advisor_profile(
        description: "An expert in technology",
        expertise: [ "AI", "Programming" ],
        account: @account
      )

      assert_equal "Expert Advisor", result[:name]
      assert_equal "A helpful expert advisor.", result[:short_description]
      assert_equal "You are an expert advisor.", result[:system_prompt]
    end

    test "generate_advisor_profile handles markdown code blocks" do
      markdown_response = <<~MARKDOWN
        ```json
        {
          "name": "Test Advisor",
          "short_description": "A test advisor.",
          "system_prompt": "You are a test advisor."
        }
        ```
      MARKDOWN

      mock_response = AI::Model::Response.new(content: markdown_response)
      mock_client = stub("client")
      mock_client.stubs(:complete).returns(mock_response)

      generator = ContentGenerator.new(client: mock_client)

      result = generator.generate_advisor_profile(
        description: "Test",
        account: @account
      )

      assert_equal "Test Advisor", result[:name]
    end

    test "generate_advisor_profile raises GenerationError on invalid JSON" do
      mock_response = AI::Model::Response.new(content: "Not valid JSON")
      mock_client = stub("client")
      mock_client.stubs(:complete).returns(mock_response)

      generator = ContentGenerator.new(client: mock_client)

      assert_raises(ContentGenerator::GenerationError) do
        generator.generate_advisor_profile(
          description: "Test",
          account: @account
        )
      end
    end

    test "generate_advisor_profile raises NoModelError when no model available" do
      # Create a new account with no models
      new_account = Account.create!(
        name: "Empty Account",
        slug: "empty-account-#{SecureRandom.hex(4)}"
      )
      set_tenant(new_account)

      generator = ContentGenerator.new

      assert_raises(ContentGenerator::NoModelError) do
        generator.generate_advisor_profile(
          description: "Test",
          account: new_account
        )
      end
    end

    # generate_council_description Tests

    test "generate_council_description returns parsed JSON" do
      json_response = {
        name: "Tech Council",
        description: "A council of technology experts."
      }.to_json

      mock_response = AI::Model::Response.new(content: json_response)
      mock_client = stub("client")
      mock_client.stubs(:complete).returns(mock_response)

      generator = ContentGenerator.new(client: mock_client)

      result = generator.generate_council_description(
        name: "Technology Council",
        purpose: "Help with technology decisions",
        account: @account
      )

      assert_equal "Tech Council", result[:name]
      assert_equal "A council of technology experts.", result[:description]
    end

    test "generate_council_description handles markdown code blocks" do
      markdown_response = <<~MARKDOWN
        Here's the council description:
        ```json
        {
          "name": "Business Council",
          "description": "Expert business advice."
        }
        ```
        Hope this helps!
      MARKDOWN

      mock_response = AI::Model::Response.new(content: markdown_response)
      mock_client = stub("client")
      mock_client.stubs(:complete).returns(mock_response)

      generator = ContentGenerator.new(client: mock_client)

      result = generator.generate_council_description(
        name: "Business",
        purpose: "Business advice",
        account: @account
      )

      assert_equal "Business Council", result[:name]
      assert_equal "Expert business advice.", result[:description]
    end

    # Caching Tests

    test "uses cache when available" do
      mock_cache = stub("cache")
      mock_cache.stubs(:fetch).yields.returns("cached value")

      generator = ContentGenerator.new(cache: mock_cache)

      result = generator.send(:fetch_from_cache, "test_key") { "computed value" }
      assert_equal "cached value", result
    end

    test "computes value when cache misses" do
      mock_cache = stub("cache")
      mock_cache.stubs(:fetch).yields.returns("computed value")

      generator = ContentGenerator.new(cache: mock_cache)

      result = generator.send(:fetch_from_cache, "test_key") { "computed value" }
      assert_equal "computed value", result
    end

    test "computes without cache when cache is nil" do
      generator = ContentGenerator.new(cache: nil)

      result = generator.send(:fetch_from_cache, "test_key") { "computed value" }
      assert_equal "computed value", result
    end

    # Template Tests

    test "render_template processes ERB correctly" do
      generator = ContentGenerator.new

      result = generator.send(:render_template, :advisor_profile,
        description: "AI expert",
        expertise: [ "Machine Learning", "NLP" ]
      )

      assert_includes result, "AI expert"
      assert_includes result, "Machine Learning"
      assert_includes result, "NLP"
    end

    test "render_template raises on unknown template" do
      generator = ContentGenerator.new

      assert_raises(ContentGenerator::GenerationError) do
        generator.send(:render_template, :unknown_template, {})
      end
    end

    # JSON Parsing Tests

    test "parse_json_response handles clean JSON" do
      generator = ContentGenerator.new
      json = '{"name": "Test", "value": 123}'

      result = generator.send(:parse_json_response, json)
      assert_equal "Test", result[:name]
      assert_equal 123, result[:value]
    end

    test "parse_json_response handles extra text before JSON" do
      generator = ContentGenerator.new
      text = 'Here is the result: {"name": "Test"}'

      result = generator.send(:parse_json_response, text)
      assert_equal "Test", result[:name]
    end

    test "parse_json_response handles extra text after JSON" do
      generator = ContentGenerator.new
      text = '{"name": "Test"} That is all.'

      result = generator.send(:parse_json_response, text)
      assert_equal "Test", result[:name]
    end

    test "parse_json_response handles nested JSON" do
      generator = ContentGenerator.new
      json = '{"outer": {"inner": "value"}}'

      result = generator.send(:parse_json_response, json)
      assert_equal({ inner: "value" }, result[:outer])
    end

    # build_client tool wiring tests

    test "build_client gives regular advisor read-only tools" do
      generator = ContentGenerator.new
      client = generator.send(:build_client, @advisor)

      tool_classes = client.tools.map(&:class)
      # All 9 read-only tools
      assert_includes tool_classes, AI::Tools::Internal::QueryMemoriesTool
      assert_includes tool_classes, AI::Tools::Internal::ListMemoriesTool
      assert_includes tool_classes, AI::Tools::Internal::ReadMemoryTool
      assert_includes tool_classes, AI::Tools::Internal::QueryConversationsTool
      assert_includes tool_classes, AI::Tools::Internal::ListConversationsTool
      assert_includes tool_classes, AI::Tools::Internal::ReadConversationTool
      assert_includes tool_classes, AI::Tools::Internal::GetConversationSummaryTool
      assert_includes tool_classes, AI::Tools::Conversations::SummarizeConversationTool
      refute_includes tool_classes, AI::Tools::Conversations::AskAdvisorTool
      assert_includes tool_classes, AI::Tools::External::BrowseWebTool
      # Write tools excluded for regular advisors
      refute_includes tool_classes, AI::Tools::Internal::CreateMemoryTool
      refute_includes tool_classes, AI::Tools::Internal::UpdateMemoryTool
      refute_includes tool_classes, AI::Tools::Conversations::FinishConversationTool
    end

    test "build_client gives scribe all tools including write tools" do
      scribe = @space.advisors.create!(
        account: @account,
        name: "Scribe",
        is_scribe: true,
        system_prompt: "You are the scribe.",
        llm_model: @llm_model
      )

      generator = ContentGenerator.new
      client = generator.send(:build_client, scribe)

      tool_classes = client.tools.map(&:class)
      # All 9 read-only tools
      assert_includes tool_classes, AI::Tools::Internal::QueryMemoriesTool
      assert_includes tool_classes, AI::Tools::Internal::ListMemoriesTool
      assert_includes tool_classes, AI::Tools::Internal::ReadMemoryTool
      assert_includes tool_classes, AI::Tools::Internal::QueryConversationsTool
      assert_includes tool_classes, AI::Tools::Internal::ListConversationsTool
      assert_includes tool_classes, AI::Tools::Internal::ReadConversationTool
      assert_includes tool_classes, AI::Tools::Internal::GetConversationSummaryTool
      assert_includes tool_classes, AI::Tools::Conversations::SummarizeConversationTool
      refute_includes tool_classes, AI::Tools::Conversations::AskAdvisorTool
      assert_includes tool_classes, AI::Tools::External::BrowseWebTool
      # All 3 write tools
      assert_includes tool_classes, AI::Tools::Internal::CreateMemoryTool
      assert_includes tool_classes, AI::Tools::Internal::UpdateMemoryTool
      assert_includes tool_classes, AI::Tools::Conversations::FinishConversationTool
    end

    test "build_client_with_system_model has no tools" do
      generator = ContentGenerator.new
      client = generator.send(:build_client_with_system_model, @account)

      assert_empty client.tools
    end

    test "advisor_tools returns 9 tools for regular advisor" do
      generator = ContentGenerator.new
      tools = generator.send(:advisor_tools, @advisor)

      assert_equal 9, tools.size
    end

    test "advisor_tools returns 22 tools for scribe" do
      scribe = @space.advisors.create!(
        account: @account,
        name: "Scribe",
        is_scribe: true,
        system_prompt: "You are the scribe.",
        llm_model: @llm_model
      )

      generator = ContentGenerator.new
      tools = generator.send(:advisor_tools, scribe)

      assert_equal 22, tools.size
    end
  end
end
