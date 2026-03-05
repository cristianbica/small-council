# frozen_string_literal: true

module AI
  module Model
    # Normalized response from any LLM provider
    class Response
      attr_reader :content, :tool_calls, :usage, :raw

      def initialize(content:, tool_calls: [], usage: nil, raw: nil)
        @content = content      # String - the text response
        @tool_calls = tool_calls # Array of ToolCall
        @usage = usage          # TokenUsage or nil
        @raw = raw              # Original provider response (for debugging)
      end

      def tool_call?
        tool_calls.any?
      end

      def to_h
        {
          content: content,
          tool_calls: tool_calls.map(&:to_h),
          usage: usage&.to_h,
          tool_call: tool_call?
        }
      end
    end

    # Represents a tool call from the LLM
    class ToolCall
      attr_reader :id, :name, :arguments

      def initialize(id:, name:, arguments: {})
        @id = id
        @name = name
        @arguments = arguments  # Hash of params
      end

      def to_h
        {
          id: id,
          name: name,
          arguments: arguments
        }
      end
    end

    # Token usage tracking for cost calculation
    class TokenUsage
      attr_reader :input_tokens, :output_tokens, :total_tokens

      def initialize(input:, output:)
        @input_tokens = input.to_i
        @output_tokens = output.to_i
        @total_tokens = @input_tokens + @output_tokens
      end

      # Calculate estimated cost based on model pricing
      # Accepts either an LLMModel instance or a hash with :input_price and :output_price
      def estimated_cost(model_or_pricing)
        pricing = if model_or_pricing.respond_to?(:input_price)
                    { input: model_or_pricing.input_price, output: model_or_pricing.output_price }
        else
                    model_or_pricing
        end

        return nil if pricing.nil?

        input_cost = input_tokens * (pricing[:input] || pricing["input"]).to_f / 1_000_000
        output_cost = output_tokens * (pricing[:output] || pricing["output"]).to_f / 1_000_000

        input_cost + output_cost
      end

      def to_h
        {
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: total_tokens
        }
      end
    end

    # Message for conversation history
    class Message
      attr_reader :role, :content, :tool_calls

      ROLES = %w[system user assistant tool].freeze

      def initialize(role:, content:, tool_calls: nil)
        raise ArgumentError, "Invalid role: #{role}" unless ROLES.include?(role)
        @role = role
        @content = content
        @tool_calls = tool_calls
      end

      def to_h
        h = { role: role, content: content }
        h[:tool_calls] = tool_calls if tool_calls
        h
      end
    end
  end
end
