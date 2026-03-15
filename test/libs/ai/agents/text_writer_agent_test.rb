# frozen_string_literal: true

require "test_helper"

module AI
  module Agents
    class TextWriterAgentTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @space = spaces(:one)
        @context = AI::Contexts::SpaceContext.new(
          account: @account,
          space: @space
        )
      end

      test "has correct system_prompt class attribute" do
        assert_equal "agents/text_writer", TextWriterAgent.system_prompt
      end

      test "is a subclass of BaseAgent" do
        agent = TextWriterAgent.new(context: @context)
        assert_kind_of BaseAgent, agent
        assert agent.is_a?(TextWriterAgent)
      end

      test "renders system_prompt via AI.prompt" do
        agent = TextWriterAgent.new(context: @context)

        AI.expects(:prompt).with("agents/text_writer", context: @context).returns("Writer prompt")

        assert_equal "Writer prompt", agent.system_prompt
      end
    end
  end
end
