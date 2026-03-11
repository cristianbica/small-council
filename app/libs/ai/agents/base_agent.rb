# frozen_string_literal: true

module AI
  module Agents
    class BaseAgent
      class_attribute :system_prompt, instance_accessor: false, instance_predicate: false
      attr_reader :tools

      def initialize(task: nil, context:, tools: nil, **)
        @task = task
        @context = context
        @tools = tools
      end

      def system_prompt
        @system_prompt ||= AI.prompt(self.class.system_prompt, context: @context)
      end
    end
  end
end
