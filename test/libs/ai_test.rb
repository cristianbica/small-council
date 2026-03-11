# frozen_string_literal: true

require "test_helper"

module AI
  class AITest < ActiveSupport::TestCase
    setup do
      @account = accounts(:one)
      set_tenant(@account)
    end

    test "AI.tool returns class for valid ref" do
      klass = AI.tool("memories/create")
      assert_equal AI::Tools::Memories::CreateMemoryTool, klass
    end

    test "AI.tool returns same class if passed a class" do
      klass = AI.tool(AI::Tools::Memories::CreateMemoryTool)
      assert_equal AI::Tools::Memories::CreateMemoryTool, klass
    end

    test "AI.tool raises ResolutionError for unknown ref" do
      assert_raises(AI::ResolutionError) do
        AI.tool("unknown/tool")
      end
    end

    test "AI.tool raises ResolutionError for unknown class name in registry" do
      # Temporarily add bad entry
      original = AI::Tools::AbstractTool::REGISTRY
      AI::Tools::AbstractTool.send(:remove_const, :REGISTRY)
      AI::Tools::AbstractTool::REGISTRY = original.merge("bad/tool" => "NonExistent::Class").freeze

      assert_raises(AI::ResolutionError) do
        AI.tool("bad/tool")
      end

      # Restore
      AI::Tools::AbstractTool.send(:remove_const, :REGISTRY)
      AI::Tools::AbstractTool::REGISTRY = original
    end

    test "AI.tools returns array of classes for single ref" do
      classes = AI.tools("memories/create")
      assert_equal 1, classes.length
      assert_equal AI::Tools::Memories::CreateMemoryTool, classes.first
    end

    test "AI.tools returns array for multiple refs" do
      classes = AI.tools("memories/create", "advisors/create")
      assert_equal 2, classes.length
      assert_includes classes, AI::Tools::Memories::CreateMemoryTool
      assert_includes classes, AI::Tools::Advisors::CreateAdvisorTool
    end

    test "AI.tools expands wildcard" do
      classes = AI.tools("memories/*")
      assert classes.length >= 5
      assert_includes classes, AI::Tools::Memories::CreateMemoryTool
      assert_includes classes, AI::Tools::Memories::ListMemoriesTool
      assert_includes classes, AI::Tools::Memories::FetchMemoryTool
      assert_includes classes, AI::Tools::Memories::SearchMemoriesTool
      assert_includes classes, AI::Tools::Memories::UpdateMemoryTool
    end

    test "AI.tools removes duplicates" do
      classes = AI.tools("memories/create", "memories/*")
      memories_count = AI::Tools::AbstractTool::REGISTRY.keys.count { |k| k.start_with?("memories/") }
      assert_equal memories_count, classes.length
    end

    test "AI.tools returns empty array for unknown ref" do
      result = AI.tools("unknown/tool")
      assert_empty result
    end

    test "AI.tools handles advisors wildcard" do
      classes = AI.tools("advisors/*")
      assert_equal 4, classes.length
      assert_includes classes, AI::Tools::Advisors::CreateAdvisorTool
      assert_includes classes, AI::Tools::Advisors::ListAdvisorsTool
      assert_includes classes, AI::Tools::Advisors::FetchAdvisorTool
      assert_includes classes, AI::Tools::Advisors::UpdateAdvisorTool
    end

    test "AI.tools handles conversations wildcard" do
      classes = AI.tools("conversations/*")
      assert_equal 1, classes.length
      assert_includes classes, AI::Tools::Conversations::UpdateConversationTool
    end

    test "AI.generate_advisor_response calls Runner with correct parameters" do
      advisor = advisors(:one)
      message = messages(:one)

      AI::Runner.expects(:run).with(
        task: { type: :respond, prompt: nil },
        context: {
          type: :conversation,
          conversation: message.conversation,
          advisor: advisor,
          message: message
        },
        handler: :conversation_response,
        tracker: :model_interaction,
        async: true
      )

      AI.generate_advisor_response(advisor: advisor, message: message)
    end

    test "AI.generate_advisor_response passes custom prompt" do
      advisor = advisors(:one)
      message = messages(:one)

      AI::Runner.expects(:run).with(
        task: { type: :respond, prompt: :custom_prompt },
        context: anything,
        handler: :conversation_response,
        tracker: :model_interaction,
        async: true
      )

      AI.generate_advisor_response(advisor: advisor, message: message, prompt: :custom_prompt)
    end

    test "AI.run delegates to Runner with task and content payload" do
      conversation = conversations(:one)

      AI::Runner.expects(:run).with(
        task: {
          type: :text,
          prompt: "conversations/title_generator",
          tools: [ "conversations/update_conversation" ]
        },
        context: {
          type: :conversation,
          conversation: conversation
        },
        handler: nil,
        tracker: nil,
        async: true
      )

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

    test "AI.runtime_for_conversation returns OpenConversationRuntime for open roe_type" do
      conversation = conversations(:one)
      conversation.stubs(:roe_type).returns("open")

      runtime = AI.runtime_for_conversation(conversation)

      assert_instance_of AI::Runtimes::OpenConversationRuntime, runtime
      assert_equal conversation, runtime.conversation
    end

    test "AI.runtime_for_conversation returns ConsensusConversationRuntime for consensus roe_type" do
      conversation = conversations(:one)
      conversation.stubs(:roe_type).returns("consensus")

      runtime = AI.runtime_for_conversation(conversation)

      assert_instance_of AI::Runtimes::ConsensusConversationRuntime, runtime
    end

    test "AI.runtime_for_conversation returns BrainstormingConversationRuntime for brainstorming roe_type" do
      conversation = conversations(:one)
      conversation.stubs(:roe_type).returns("brainstorming")

      runtime = AI.runtime_for_conversation(conversation)

      assert_instance_of AI::Runtimes::BrainstormingConversationRuntime, runtime
    end

    test "AI.runtime_for_conversation defaults to Open for unknown roe_type" do
      conversation = conversations(:one)
      conversation.stubs(:roe_type).returns("unknown")

      runtime = AI.runtime_for_conversation(conversation)

      assert_instance_of AI::Runtimes::OpenConversationRuntime, runtime
    end
  end
end
