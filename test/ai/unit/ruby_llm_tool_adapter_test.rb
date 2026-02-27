# frozen_string_literal: true

require "test_helper"

module AI
  module Adapters
    class RubyLLMToolAdapterTest < ActiveSupport::TestCase
      setup do
        @test_tool = TestHelperTool.new
        @adapter = RubyLLMToolAdapter.new(@test_tool)
        @ruby_llm_tool = @adapter.to_ruby_llm_tool
      end

      # Test tool class for adapter tests
      class TestHelperTool < AI::Tools::BaseTool
        def description
          "A test tool for verifying adapter behavior"
        end

        def parameters
          {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "The search query"
              },
              count: {
                type: "integer",
                description: "Number of results"
              },
              enabled: {
                type: "boolean",
                description: "Whether to enable"
              },
              tags: {
                type: "array",
                description: "List of tags"
              }
            },
            required: [ :query ]
          }
        end

        def execute(arguments = {}, context = {})
          {
            query: arguments[:query] || arguments["query"],
            count: arguments[:count] || arguments["count"],
            context_keys: context.keys,
            success: true
          }
        end
      end

      test "initializes with AI tool" do
        assert_equal @test_tool, @adapter.ai_tool
      end

      test "exposes context accessor" do
        assert_equal({}, @adapter.context)

        @adapter.context = { space: "test", user: "user1" }
        assert_equal({ space: "test", user: "user1" }, @adapter.context)
      end

      test "to_ruby_llm_tool returns RubyLLM::Tool instance" do
        assert_kind_of RubyLLM::Tool, @ruby_llm_tool
        assert_respond_to @ruby_llm_tool, :execute
      end

      test "execute passes arguments and context to tool" do
        @adapter.context = { space: "my_space", user: "my_user" }

        result_json = @ruby_llm_tool.execute(query: "test", count: 5)
        result = JSON.parse(result_json, symbolize_names: true)

        assert_equal "test", result[:query]
        assert_equal 5, result[:count]
        # Context keys may be strings or symbols
        context_keys = result[:context_keys].map(&:to_s)
        assert_includes context_keys, "space"
        assert_includes context_keys, "user"
        assert result[:success]
      end

      test "execute handles string argument keys" do
        @adapter.context = { space: "my_space" }

        # RubyLLM may pass string or symbol keys
        result_json = @ruby_llm_tool.execute("query" => "string_key_test", "count" => 3)
        result = JSON.parse(result_json, symbolize_names: true)

        # Tool receives both formats; adapter ensures they work
        assert_equal "string_key_test", result[:query]
      end

      test "execute returns JSON string" do
        @adapter.context = { space: "test" }

        result = @ruby_llm_tool.execute(query: "hello")

        assert_kind_of String, result
        # Should be valid JSON
        parsed = JSON.parse(result)
        assert parsed.key?("query")
        assert parsed.key?("success")
      end

      test "execute catches errors and returns error JSON" do
        # Create a tool that will raise an error
        error_tool = Class.new(AI::Tools::BaseTool) do
          def description
            "Error tool"
          end

          def parameters
            { type: "object", properties: {} }
          end

          def execute(_arguments, _context)
            raise StandardError, "Something went wrong"
          end
        end.new

        error_adapter = RubyLLMToolAdapter.new(error_tool)
        error_ruby_llm_tool = error_adapter.to_ruby_llm_tool
        error_adapter.context = {}

        result_json = error_ruby_llm_tool.execute(**{})
        result = JSON.parse(result_json, symbolize_names: true)

        assert result.key?(:error)
        assert_match(/Something went wrong/, result[:error])
      end

      test "adapter is compatible with RubyLLM::Tool interface" do
        # Verify the returned tool can be used where RubyLLM::Tool is expected
        assert_kind_of RubyLLM::Tool, @ruby_llm_tool

        # RubyLLM::Tool interface methods
        assert_respond_to @ruby_llm_tool, :name
        assert_respond_to @ruby_llm_tool, :description
        assert_respond_to @ruby_llm_tool, :execute
      end

      test "complex tool integration" do
        # More complex tool simulating real usage
        complex_tool = Class.new(AI::Tools::BaseTool) do
          def description
            "Complex query tool"
          end

          def parameters
            {
              type: "object",
              properties: {
                filters: {
                  type: "object",
                  description: "Filter criteria"
                },
                sort: {
                  type: "string",
                  enum: [ "asc", "desc" ],
                  description: "Sort order"
                }
              },
              required: [ :filters ]
            }
          end

          def execute(args, context)
            {
              results: [],
              filters_received: args[:filters] || args["filters"],
              sort_received: args[:sort] || args["sort"],
              context_present: context.present?
            }
          end
        end.new

        complex_adapter = RubyLLMToolAdapter.new(complex_tool)
        complex_ruby_llm_tool = complex_adapter.to_ruby_llm_tool
        complex_adapter.context = { space: "test" }

        result_json = complex_ruby_llm_tool.execute(
          filters: { status: "active" },
          sort: "desc"
        )
        result = JSON.parse(result_json, symbolize_names: true)

        assert result[:context_present]
        # Filters may have string or symbol keys
        filters_received = result[:filters_received].transform_keys(&:to_s)
        assert_equal({ "status" => "active" }, filters_received)
        assert_equal "desc", result[:sort_received]
      end
    end
  end
end
