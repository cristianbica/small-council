# frozen_string_literal: true

require "test_helper"

module AI
  module Agents
    class AdvisorAgentTest < ActiveSupport::TestCase
      ContextStub = Struct.new(:tools)

      test "uses initializer tools when provided" do
        explicit_tools = [ { "ref" => "conversations/update_conversation", "policy" => "allow" } ]
        agent = AdvisorAgent.new(context: ContextStub.new([]), tools: explicit_tools)

        assert_equal explicit_tools, agent.tools
      end

      test "falls back to context tools" do
        context_tools = [ { "ref" => "memories/create", "policy" => "allow" } ]
        agent = AdvisorAgent.new(context: ContextStub.new(context_tools))

        assert_equal context_tools, agent.tools
      end

      test "defaults to empty tools when context has none" do
        agent = AdvisorAgent.new(context: ContextStub.new(nil))

        assert_equal [], agent.tools
      end
    end
  end
end
