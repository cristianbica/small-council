# frozen_string_literal: true

module AI
  module Tasks
    class TextTask < BaseTask
      self.agent = :text_writer

      attr_reader :description

      def initialize(context:, prompt:, schema: nil, description: nil, tools: nil)
        super(context: context, tools: tools)
        @description = description
        @configured_prompt = prompt
        @configured_schema = schema
      end

      def prompt
        @prompt ||= AI.prompt(@configured_prompt, context: context, task: self)
      end

      def schema
        AI.schema(@configured_schema) if @configured_schema
      end

      def prepare(chat)
        chat.schema schema if schema
        chat.instructions agent.system_prompt
        chat.add_message content: prompt
      end
    end
  end
end
