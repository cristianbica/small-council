# frozen_string_literal: true

require "ruby_llm"

module AI
  module Adapters
    # Adapter that converts our BaseTool interface to RubyLLM::Tool interface
    # This is used internally by AI::Client and should not be called directly
    #
    # The adapter creates a dynamic RubyLLM::Tool subclass that delegates
    # execution to our AI tool with proper context handling.
    #
    class RubyLLMToolAdapter
      # Context is stored at adapter level (passed from Client during chat)
      attr_accessor :context

      def initialize(ai_tool)
        @ai_tool = ai_tool
        @context = {}  # Set by Client before execution
        @tool_class = create_tool_class(ai_tool)
      end

      # Returns a RubyLLM::Tool-compatible instance
      def to_ruby_llm_tool
        @tool_class.new
      end

      # Access the wrapped tool
      attr_reader :ai_tool

      private

      def create_tool_class(ai_tool)
        tool_instance = ai_tool
        context_holder = self

        Class.new(RubyLLM::Tool) do
          # Set description at class level
          description tool_instance.description

          # Define parameters from tool schema
          schema = tool_instance.parameters
          if schema.is_a?(Hash) && schema[:properties]
            schema[:properties].each do |name, config|
              param_type = config[:type]&.to_sym || :string
              param_desc = config[:description] || ""
              required = schema[:required]&.include?(name.to_s) || schema[:required]&.include?(name.to_sym) || false

              param name,
                    type: param_type,
                    desc: param_desc,
                    required: required
            end
          end

          # Override execute to call our tool with context
          define_method :execute do |**args|
            result = tool_instance.execute(args, context_holder.context)
            result.is_a?(String) ? result : result.to_json
          rescue => e
            Rails.logger.error "[RubyLLMToolAdapter] #{tool_instance.name} failed: #{e.message}"
            { error: e.message }.to_json
          end
        end
      end
    end
  end
end
