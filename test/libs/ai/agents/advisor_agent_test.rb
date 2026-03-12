# frozen_string_literal: true

require "test_helper"

module AI
  module Agents
    class AdvisorAgentTest < ActiveSupport::TestCase
      ContextStub = Struct.new(:scribe?)

      test "uses initializer tools when provided" do
        agent = AdvisorAgent.new(context: ContextStub.new(false), tools: [ "conversations/update_conversation" ])

        assert_equal [ "conversations/update_conversation" ], agent.tools
      end

      test "defaults scribe tools to memories and internet wildcards" do
        agent = AdvisorAgent.new(context: ContextStub.new(true))

        assert_equal [ "memories/*", "internet/browse_web" ], agent.tools
      end

      test "defaults to no tools for non-scribe context" do
        agent = AdvisorAgent.new(context: ContextStub.new(false))

        assert_equal [], agent.tools
      end
    end
  end
end
