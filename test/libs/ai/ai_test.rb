# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AI
  class AITest < ActiveSupport::TestCase
    test "resolves known constants for context/task/agent/handler/tracker/schema" do
      assert_equal AI::Contexts::ConversationContext, AI.context(:conversation)
      assert_equal AI::Tasks::RespondTask, AI.task(:respond)
      assert_equal AI::Agents::AdvisorAgent, AI.agent(:advisor)
      assert_equal AI::Handlers::ConversationResponseHandler, AI.handler(:conversation_response)
      assert_equal AI::Trackers::ModelInteractionTracker, AI.tracker(:model_interaction)
      assert_equal AI::Schemas::AdvisorProfileSchema, AI.schema(:advisor_profile)
    end

    test "returns passed class references unchanged" do
      assert_equal AI::Contexts::ConversationContext, AI.context(AI::Contexts::ConversationContext)
      assert_equal AI::Tasks::RespondTask, AI.task(AI::Tasks::RespondTask)
      assert_equal AI::Agents::AdvisorAgent, AI.agent(AI::Agents::AdvisorAgent)
      assert_equal AI::Handlers::ConversationResponseHandler, AI.handler(AI::Handlers::ConversationResponseHandler)
      assert_equal AI::Trackers::UsageTracker, AI.tracker(AI::Trackers::UsageTracker)
      assert_equal AI::Schemas::AdvisorProfileSchema, AI.schema(AI::Schemas::AdvisorProfileSchema)
    end

    test "raises resolution error for unknown references" do
      assert_raises(AI::ResolutionError) { AI.context(:missing) }
      assert_raises(AI::ResolutionError) { AI.task(:missing) }
      assert_raises(AI::ResolutionError) { AI.agent(:missing) }
      assert_raises(AI::ResolutionError) { AI.handler(:missing) }
      assert_raises(AI::ResolutionError) { AI.tracker(:missing) }
      assert_raises(AI::ResolutionError) { AI.schema(:missing) }
      assert_raises(AI::ResolutionError) { AI.prompt("missing/prompt") }
      assert_raises(AI::ResolutionError) { AI.tool("missing/tool") }
    end

    test "tool resolves registry entries and tools supports wildcard lookup" do
      assert_equal AI::Tools::Memories::CreateMemoryTool, AI.tool("memories/create")

      result = AI.tools("memories/*")
      assert result.include?(AI::Tools::Memories::CreateMemoryTool)
      assert result.include?(AI::Tools::Memories::ListMemoriesTool)
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
