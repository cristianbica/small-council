# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  class AITest < ActiveSupport::TestCase
    test "resolves known constants for context/task/agent/handler/tracker/schema/command" do
      assert_equal AI::Contexts::ConversationContext, AI.context(:conversation)
      assert_equal AI::Tasks::RespondTask, AI.task(:respond)
      assert_equal AI::Agents::AdvisorAgent, AI.agent(:advisor)
      assert_equal AI::Handlers::ConversationResponseHandler, AI.handler(:conversation_response)
      assert_equal AI::Trackers::ModelInteractionTracker, AI.tracker(:model_interaction)
      assert_equal AI::Schemas::AdvisorProfileSchema, AI.schema(:advisor_profile)
      assert_equal AI::Commands::AttachCommand, AI.command(:attach)
    end

    test "returns passed class references unchanged for all resolvers" do
      assert_equal AI::Contexts::ConversationContext, AI.context(AI::Contexts::ConversationContext)
      assert_equal AI::Tasks::RespondTask, AI.task(AI::Tasks::RespondTask)
      assert_equal AI::Agents::AdvisorAgent, AI.agent(AI::Agents::AdvisorAgent)
      assert_equal AI::Handlers::ConversationResponseHandler, AI.handler(AI::Handlers::ConversationResponseHandler)
      assert_equal AI::Trackers::UsageTracker, AI.tracker(AI::Trackers::UsageTracker)
      assert_equal AI::Schemas::AdvisorProfileSchema, AI.schema(AI::Schemas::AdvisorProfileSchema)
      assert_equal AI::Commands::MemoryCommand, AI.command(AI::Commands::MemoryCommand)
      assert_equal AI::Tools::Memories::CreateMemoryTool, AI.tool(AI::Tools::Memories::CreateMemoryTool)
    end

    test "resolvers raise ResolutionError for invalid string types" do
      assert_raises(AI::ResolutionError) { AI.context("invalid_type") }
      assert_raises(AI::ResolutionError) { AI.task("invalid_type") }
      assert_raises(AI::ResolutionError) { AI.agent("invalid_type") }
      assert_raises(AI::ResolutionError) { AI.handler("invalid_type") }
      assert_raises(AI::ResolutionError) { AI.tracker("invalid_type") }
      assert_raises(AI::ResolutionError) { AI.schema("invalid_type") }
      assert_raises(AI::ResolutionError) { AI.command("invalid_type") }
    end

    test "tool raises ResolutionError for unknown tool reference" do
      assert_raises(AI::ResolutionError) { AI.tool("unknown/tool") }
    end

    test "tools supports multiple wildcard patterns" do
      result = AI.tools("memories/*", "advisors/*")
      assert result.include?(AI::Tools::Memories::CreateMemoryTool)
      assert result.include?(AI::Tools::Advisors::ListAdvisorsTool)
    end

    test "prompt raises ResolutionError for non-existent prompt file" do
      assert_raises(AI::ResolutionError) { AI.prompt("nonexistent/prompt") }
    end

    test "tools returns empty array when no matching tools" do
      result = AI.tools("nonexistent/*")
      assert_empty result
    end

    test "tools returns specific tool when exact match" do
      result = AI.tools("memories/create")
      assert_includes result, AI::Tools::Memories::CreateMemoryTool
    end

    test "compact_conversation delegates to runner with correct parameters" do
      message = messages(:one)

      AI::Runner.expects(:run).with do |args|
        assert_equal :text, args.dig(:task, :type)
        assert_equal "agents/conversation_compactor", args.dig(:task, :prompt)
        assert_equal :conversation, args.dig(:context, :type)
        assert_equal message.conversation, args.dig(:context, :conversation)
        assert_equal message.sender, args.dig(:context, :advisor)
        assert_equal message, args.dig(:context, :message)
        assert_equal :model_interaction, args[:tracker]
        assert_equal true, args[:async]
        true
      end

      AI.compact_conversation(message: message)
    end

    test "raises resolution error for unknown references" do
      assert_raises(AI::ResolutionError) { AI.context(:missing) }
      assert_raises(AI::ResolutionError) { AI.task(:missing) }
      assert_raises(AI::ResolutionError) { AI.agent(:missing) }
      assert_raises(AI::ResolutionError) { AI.handler(:missing) }
      assert_raises(AI::ResolutionError) { AI.tracker(:missing) }
      assert_raises(AI::ResolutionError) { AI.schema(:missing) }
      assert_raises(AI::ResolutionError) { AI.command(:missing) }
      assert_raises(AI::ResolutionError) { AI.prompt("missing/prompt") }
      assert_raises(AI::ResolutionError) { AI.tool("missing/tool") }
    end

    test "tool resolves registry entries and tools supports wildcard lookup" do
      assert_equal AI::Tools::Memories::CreateMemoryTool, AI.tool("memories/create")

      result = AI.tools("memories/*")
      assert result.include?(AI::Tools::Memories::CreateMemoryTool)
      assert result.include?(AI::Tools::Memories::ListMemoriesTool)
    end

    test "tool returns class reference unchanged" do
      tool_class = AI::Tools::Memories::CreateMemoryTool
      assert_equal tool_class, AI.tool(tool_class)
    end

    test "prompt renders erb with locals" do
      body = AI.prompt("tasks/conversation_title", task: OpenStruct.new(description: "Coverage Sprint"))
      assert_match(/Coverage Sprint/, body)
    end

    test "generate helpers delegate to runner" do
      runner_payload = {}
      AI::Runner.expects(:run).twice.with do |args|
        runner_payload = args
        true
      end

      space = spaces(:one)
      message = messages(:one)
      advisor = advisors(:one)

      AI.generate_text(description: "d", prompt: "p", space: space, async: false)
      assert_equal :text, runner_payload.dig(:task, :type)
      assert_equal :space, runner_payload.dig(:context, :type)

      AI.generate_advisor_response(advisor: advisor, message: message, prompt: "p", async: true)
      assert_equal :respond, runner_payload.dig(:task, :type)
      assert_equal :conversation, runner_payload.dig(:context, :type)
    end

    test "generate_text passes schema parameter" do
      runner_payload = {}
      AI::Runner.expects(:run).once.with do |args|
        runner_payload = args
        true
      end

      space = spaces(:one)
      AI.generate_text(description: "test", prompt: "prompt", schema: :advisor_profile, space: space)

      assert_equal :advisor_profile, runner_payload.dig(:task, :schema)
    end

    test "generate_text passes handler parameter" do
      runner_payload = {}
      AI::Runner.expects(:run).once.with do |args|
        runner_payload = args
        true
      end

      space = spaces(:one)
      AI.generate_text(description: "test", prompt: "prompt", space: space, handler: :custom_handler)

      assert_equal :custom_handler, runner_payload[:handler]
    end

    test "generate_advisor_response uses default tracker" do
      runner_payload = {}
      AI::Runner.expects(:run).once.with do |args|
        runner_payload = args
        true
      end

      message = messages(:one)
      advisor = advisors(:one)
      AI.generate_advisor_response(advisor: advisor, message: message)

      assert_equal :model_interaction, runner_payload[:tracker]
    end

    test "generate_advisor_response passes custom tracker" do
      runner_payload = {}
      AI::Runner.expects(:run).once.with do |args|
        runner_payload = args
        true
      end

      message = messages(:one)
      advisor = advisors(:one)
      AI.generate_advisor_response(advisor: advisor, message: message, tracker: :usage)

      assert_equal :usage, runner_payload[:tracker]
    end

    test "run passes all parameters to Runner" do
      conversation = conversations(:one)

      AI::Runner.expects(:run).with(
        task: { type: :test },
        context: { type: :conversation },
        handler: :test_handler,
        tracker: :test_tracker,
        async: true
      )

      AI.run(
        task: { type: :test },
        context: { type: :conversation },
        handler: :test_handler,
        tracker: :test_tracker,
        async: true
      )
    end

    test "run delegates to Runner.run with task/content payload" do
      conversation = conversations(:one)

      AI::Runner.expects(:run).with do |args|
        assert_equal :text, args.dig(:task, :type)
        assert_equal "conversations/title_generator", args.dig(:task, :prompt)
        assert_equal [ "conversations/update_conversation" ], args.dig(:task, :tools)
        assert_equal :conversation, args.dig(:context, :type)
        assert_equal conversation, args.dig(:context, :conversation)
        assert_equal true, args[:async]
        true
      end

      AI.run(
        task: {
          type: :text,
          prompt: "conversations/title_generator",
          tools: [ "conversations/update_conversation" ]
        },
        context: { type: :conversation, conversation: conversation },
        async: true
      )
    end

    test "runtime_for_conversation selects expected runtime" do
      open = OpenStruct.new(roe_type: "open")
      consensus = OpenStruct.new(roe_type: "consensus")
      brainstorming = OpenStruct.new(roe_type: "brainstorming")
      unknown = OpenStruct.new(roe_type: "other")

      assert_instance_of AI::Runtimes::OpenConversationRuntime, AI.runtime_for_conversation(open)
      assert_instance_of AI::Runtimes::ConsensusConversationRuntime, AI.runtime_for_conversation(consensus)
      assert_instance_of AI::Runtimes::BrainstormingConversationRuntime, AI.runtime_for_conversation(brainstorming)
      assert_instance_of AI::Runtimes::OpenConversationRuntime, AI.runtime_for_conversation(unknown)
    end
  end
end
