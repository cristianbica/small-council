# frozen_string_literal: true

require "test_helper"

module AI
  module Agents
    class BaseAgentTest < ActiveSupport::TestCase
      class TestAgent < BaseAgent
        self.system_prompt = "agents/test_agent"
      end

      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @space = spaces(:one)
        @context = AI::Contexts::SpaceContext.new(
          account: @account,
          space: @space
        )
      end

      test "initialize stores task context and tools" do
        task = mock("task")
        tools = [ "tool1", "tool2" ]

        agent = TestAgent.new(task: task, context: @context, tools: tools)

        assert_equal tools, agent.tools
      end

      test "initialize with minimal arguments" do
        agent = TestAgent.new(context: @context)

        assert_nil agent.tools
      end

      test "system_prompt renders from class attribute" do
        agent = TestAgent.new(context: @context)

        # Should call AI.prompt with the class system_prompt
        AI.expects(:prompt).with("agents/test_agent", context: @context).returns("Rendered prompt")

        assert_equal "Rendered prompt", agent.system_prompt
      end

      test "system_prompt is memoized" do
        agent = TestAgent.new(context: @context)

        AI.expects(:prompt).once.returns("Rendered prompt")

        # Call twice
        agent.system_prompt
        agent.system_prompt
      end

      test "base agent without system_prompt class attribute" do
        class NoPromptAgent < BaseAgent
        end

        agent = NoPromptAgent.new(context: @context)

        # Should call AI.prompt with nil
        AI.expects(:prompt).with(nil, context: @context).returns("Default prompt")

        assert_equal "Default prompt", agent.system_prompt
      end
    end
  end
end
