# frozen_string_literal: true

module AI
  module Agents
    class BaseAgent
      class_attribute :system_prompt, instance_accessor: false, instance_predicate: false

      def initialize(task: nil, context:, **)
        @task = task
        @context = context
      end

      def system_prompt
        @system_prompt ||= AI.prompt(self.class.system_prompt)
      end

      def tools
        []
      end
    end
  end
end
