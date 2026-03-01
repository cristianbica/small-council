# frozen_string_literal: true

module AI
  module Tools
    # Base class for all AI tools - unified interface
    #
    # Tools are STATELESS - initialized without context.
    # Context is passed at execution time via execute(arguments, context).
    #
    # Example:
    #   class MyTool < BaseTool
    #     def description
    #       "Does something useful"
    #     end
    #
    #     def parameters
    #       {
    #         type: "object",
    #         properties: {
    #           query: { type: "string", description: "Search query" }
    #         },
    #         required: [:query]
    #       }
    #     end
    #
    #     def execute(arguments = {}, context = {})
    #       validate_context!(context, :space)
    #       # Do work with context[:space]
    #       { success: true, result: "Found something" }
    #     end
    #   end
    #
    class BaseTool
      # Tool metadata - used by LLM
      def name
        return "unnamed" unless self.class.name.present?
        self.class.name.demodulize.underscore.gsub("_tool", "")
      end

      def display_name
        name.humanize.titleize
      end

      # Description of what this tool does
      # Override in subclasses
      def description
        raise NotImplementedError, "#{self.class} must implement #description"
      end

      # Parameter schema in JSON Schema-like format
      # Override in subclasses
      #
      # Example return value:
      # {
      #   type: "object",
      #   properties: {
      #     query: { type: "string", description: "..." },
      #     limit: { type: "integer", description: "..." }
      #   },
      #   required: [:query]
      # }
      def parameters
        raise NotImplementedError, "#{self.class} must implement #parameters"
      end

      # Execute the tool - called when LLM invokes tool
      # Context is passed at execution time, not initialization
      #
      # @param arguments [Hash] Arguments from LLM
      # @param context [Hash] Execution context (space, conversation, user, advisor, etc.)
      # @return [Hash] Result that can be serialized to JSON
      def execute(arguments = {}, context = {})
        raise NotImplementedError, "#{self.class} must implement #execute"
      end

      # Convert to RubyLLM tool format (internal use only)
      def to_ruby_llm_tool
        AI::Adapters::RubyLLMToolAdapter.new(self)
      end

      protected

      # Validate that required context keys are present
      def validate_context!(context, *required_keys)
        missing = required_keys - context.keys
        if missing.any?
          raise ArgumentError, "Missing required context: #{missing.join(', ')}"
        end
      end
    end
  end
end
