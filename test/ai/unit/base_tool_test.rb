# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    class BaseToolTest < ActiveSupport::TestCase
      # Test tool implementing the interface
      class TestTool < BaseTool
        def description
          "A test tool for unit testing"
        end

        def parameters
          {
            type: "object",
            properties: {
              query: { type: "string", description: "Search query" },
              limit: { type: "integer", description: "Result limit" }
            },
            required: [ :query ]
          }
        end

        def execute(arguments = {}, context = {})
          validate_context!(context, :space)
          { success: true, query: arguments[:query], space_id: context[:space]&.id }
        end
      end

      # Tool missing required methods
      class IncompleteTool < BaseTool; end

      setup do
        @tool = TestTool.new
      end

      test "name is derived from class name" do
        assert_equal "test", @tool.name
      end

      test "display_name humanizes and titleizes name" do
        assert_equal "Test", @tool.display_name
      end

      test "name handles nested module names" do
        tool = AI::Tools::Internal::QueryMemoriesTool.new
        assert_equal "query_memories", tool.name
      end

      test "description must be implemented" do
        incomplete = IncompleteTool.new
        assert_raises(NotImplementedError) { incomplete.description }
      end

      test "parameters must be implemented" do
        incomplete = IncompleteTool.new
        assert_raises(NotImplementedError) { incomplete.parameters }
      end

      test "execute must be implemented" do
        incomplete = IncompleteTool.new
        assert_raises(NotImplementedError) { incomplete.execute }
      end

      test "validate_context! passes when all keys present" do
        context = { space: "present", user: "present" }
        # Should not raise
        assert_nothing_raised do
          @tool.send(:validate_context!, context, :space, :user)
        end
      end

      test "validate_context! raises when keys missing" do
        context = { space: "present" }
        error = assert_raises(ArgumentError) do
          @tool.send(:validate_context!, context, :space, :user, :advisor)
        end
        assert_match(/Missing required context: user, advisor/, error.message)
      end

      test "validate_context! in execute enforces requirements" do
        error = assert_raises(ArgumentError) do
          @tool.execute({ query: "test" }, {})  # Missing :space
        end
        assert_match(/Missing required context: space/, error.message)
      end

      test "to_ruby_llm_tool creates adapter" do
        adapter = @tool.to_ruby_llm_tool
        assert_instance_of AI::Adapters::RubyLLMToolAdapter, adapter
        assert_equal @tool, adapter.ai_tool
      end

      test "full execution flow works" do
        space = Struct.new(:id).new(123)
        result = @tool.execute({ query: "test" }, { space: space })

        assert result[:success]
        assert_equal "test", result[:query]
        assert_equal 123, result[:space_id]
      end
    end
  end
end
