# frozen_string_literal: true

module AI
  module Tasks
    class BaseTask
      class_attribute :agent, instance_accessor: false, instance_predicate: false


      attr_reader :context

      def initialize(context:)
        @context = context
      end

      def agent
        klass = AI.agent(self.class.agent)
        klass.new(task: self, context: context)
      end

      def run(result, trackers: [])
        chat = AI::Client.chat(model: context.model)
        register_tools(chat)
        prepare(chat)
        register_trackers(chat, trackers)
        chat.complete(result)
        result
      end

      def prepare(_chat)
        raise NotImplementedError, "#{self.class} must implement #prepare"
      end

      private

      def register_tools(chat)
        refs = Array(agent.tools)
        return if refs.empty?

        tools = AI.tools(*refs).map { |klass| klass.new(context) }
        chat.tools(tools)
      end

      def register_trackers(chat, trackers)
        Array(trackers).each do |tracker|
          next unless tracker.respond_to?(:register)

          chat.register_tracker(tracker)
        end
      end
    end
  end
end
