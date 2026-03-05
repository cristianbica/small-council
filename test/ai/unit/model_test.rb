# frozen_string_literal: true

require "test_helper"

module AI
  module Model
    class ResponseTest < ActiveSupport::TestCase
      test "initializes with content only" do
        response = Response.new(content: "Hello world")
        assert_equal "Hello world", response.content
        assert_empty response.tool_calls
        assert_nil response.usage
        assert_nil response.raw
      end

      test "initializes with all parameters" do
        usage = TokenUsage.new(input: 10, output: 5)
        tool_call = ToolCall.new(id: "tc-1", name: "search", arguments: { query: "test" })

        response = Response.new(
          content: "Result",
          tool_calls: [ tool_call ],
          usage: usage,
          raw: { some: "data" }
        )

        assert_equal "Result", response.content
        assert_equal 1, response.tool_calls.length
        assert_equal usage, response.usage
        assert_equal({ some: "data" }, response.raw)
      end

      test "tool_call? returns true when tool_calls present" do
        response_with_tools = Response.new(
          content: "",
          tool_calls: [ ToolCall.new(id: "1", name: "test", arguments: {}) ]
        )
        assert response_with_tools.tool_call?

        response_without_tools = Response.new(content: "Hello")
        assert_not response_without_tools.tool_call?
      end

      test "to_h returns serializable hash" do
        usage = TokenUsage.new(input: 10, output: 5)
        tool_call = ToolCall.new(id: "tc-1", name: "search", arguments: { query: "test" })

        response = Response.new(
          content: "Result",
          tool_calls: [ tool_call ],
          usage: usage,
          raw: nil
        )

        hash = response.to_h
        assert_equal "Result", hash[:content]
        assert_equal [ { id: "tc-1", name: "search", arguments: { query: "test" } } ], hash[:tool_calls]
        assert_equal({ input_tokens: 10, output_tokens: 5, total_tokens: 15 }, hash[:usage])
        assert hash[:tool_call]
      end
    end

    class ToolCallTest < ActiveSupport::TestCase
      test "initializes with required parameters" do
        tool_call = ToolCall.new(
          id: "call-123",
          name: "query_memories",
          arguments: { query: "test", limit: 5 }
        )

        assert_equal "call-123", tool_call.id
        assert_equal "query_memories", tool_call.name
        assert_equal({ query: "test", limit: 5 }, tool_call.arguments)
      end

      test "to_h returns serializable hash" do
        tool_call = ToolCall.new(
          id: "call-123",
          name: "query_memories",
          arguments: { query: "test" }
        )

        assert_equal(
          { id: "call-123", name: "query_memories", arguments: { query: "test" } },
          tool_call.to_h
        )
      end
    end

    class TokenUsageTest < ActiveSupport::TestCase
      test "initializes and calculates total" do
        usage = TokenUsage.new(input: 100, output: 50)
        assert_equal 100, usage.input_tokens
        assert_equal 50, usage.output_tokens
        assert_equal 150, usage.total_tokens
      end

      test "handles string inputs" do
        usage = TokenUsage.new(input: "100", output: "50")
        assert_equal 100, usage.input_tokens
        assert_equal 50, usage.output_tokens
        assert_equal 150, usage.total_tokens
      end

      test "estimated_cost with LLMModel" do
        usage = TokenUsage.new(input: 1_000_000, output: 500_000)

        # Mock model with pricing
        model = Struct.new(:input_price, :output_price).new(2.5, 10.0)
        cost = usage.estimated_cost(model)

        # Input: 1M tokens @ $2.5 per 1M = $2.5
        # Output: 500K tokens @ $10 per 1M = $5.0
        # Total: $7.5
        assert_in_delta 7.5, cost, 0.01
      end

      test "estimated_cost with hash pricing" do
        usage = TokenUsage.new(input: 1_000_000, output: 500_000)

        pricing = { input: 2.5, output: 10.0 }
        cost = usage.estimated_cost(pricing)

        assert_in_delta 7.5, cost, 0.01
      end

      test "estimated_cost with string keys" do
        usage = TokenUsage.new(input: 1_000_000, output: 500_000)

        pricing = { "input" => 2.5, "output" => 10.0 }
        cost = usage.estimated_cost(pricing)

        assert_in_delta 7.5, cost, 0.01
      end

      test "estimated_cost returns nil with nil pricing" do
        usage = TokenUsage.new(input: 100, output: 50)
        assert_nil usage.estimated_cost(nil)
      end

      test "to_h returns serializable hash" do
        usage = TokenUsage.new(input: 100, output: 50)
        assert_equal(
          { input_tokens: 100, output_tokens: 50, total_tokens: 150 },
          usage.to_h
        )
      end
    end

    class MessageTest < ActiveSupport::TestCase
      test "initializes with valid roles" do
        Message::ROLES.each do |role|
          msg = Message.new(role: role, content: "Test")
          assert_equal role, msg.role
        end
      end

      test "raises on invalid role" do
        assert_raises(ArgumentError) do
          Message.new(role: "invalid", content: "Test")
        end
      end

      test "to_h returns serializable hash" do
        msg = Message.new(role: "user", content: "Hello")
        assert_equal({ role: "user", content: "Hello" }, msg.to_h)
      end

      test "to_h includes tool_calls when present" do
        msg = Message.new(role: "assistant", content: "", tool_calls: [ { name: "test" } ])
        assert_equal({ role: "assistant", content: "", tool_calls: [ { name: "test" } ] }, msg.to_h)
      end
    end
  end
end
