# frozen_string_literal: true

module AI
  module Tasks
    class BaseTask
      class_attribute :agent, instance_accessor: false, instance_predicate: false


      attr_reader :context

      def initialize(context:, tools: nil)
        @context = context
        @agent_tools = tools
      end

      def agent
        klass = AI.agent(self.class.agent)
        klass.new(task: self, context: context, tools: @agent_tools)
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
        agent.tools&.each do |tool|
          next unless tool["policy"].to_s.downcase == "allow"

          klass = AI.tool(tool["ref"])
          chat.tools(klass.new(context)) if klass
        end
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
