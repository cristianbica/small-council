# frozen_string_literal: true

module AI
  module Handlers
    class BaseHandler
      attr_reader :task, :context

      def initialize(task: nil, context: nil, **)
        @task = task
        @context = context
      end

      def handle(_result)
        raise NotImplementedError, "#{self.class} must implement #handle"
      end
    end
  end
end
