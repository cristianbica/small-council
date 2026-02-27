# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class QueryMemoriesToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @tool = QueryMemoriesTool.new
        end

        test "name returns query_memories" do
          assert_equal "query_memories", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
          assert @tool.description.include?("Search")
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:query)
          assert params[:properties].key?(:memory_type)
          assert params[:properties].key?(:limit)
          assert_includes params[:required], :query
        end

        test "execute returns error without context" do
          error = assert_raises(ArgumentError) do
            @tool.execute({ query: "test" }, {})
          end
          assert_match(/Missing required context: space/, error.message)
        end

        test "execute returns error without query" do
          result = @tool.execute({}, { space: @space })
          assert_not result[:success]
          assert_equal "Query parameter is required", result[:error]
        end

        test "execute searches memories by query" do
          # Create some memories with unique content
          Memory.create!(
            account: @account,
            space: @space,
            title: "Project Timeline XYZ",
            content: "The project will be completed by March",
            memory_type: "knowledge",
            status: "active"
          )
          Memory.create!(
            account: @account,
            space: @space,
            title: "Meeting Notes XYZ",
            content: "Discussed budget for Q2 timeline",
            memory_type: "knowledge",
            status: "active"
          )
          # Create an archived memory (should not appear)
          Memory.create!(
            account: @account,
            space: @space,
            title: "Old Timeline XYZ",
            content: "Original dates were different",
            memory_type: "knowledge",
            status: "archived"
          )

          result = @tool.execute({ query: "XYZ" }, { space: @space })

          assert result[:success]
          assert result[:count] >= 2
          assert result[:memories].length >= 2
          assert result[:memories].all? { |m| m[:title].include?("XYZ") }
        end

        test "execute filters by memory_type" do
          # Create different memory types
          Memory.create!(
            account: @account,
            space: @space,
            title: "Space Summary",
            content: "This is the main summary",
            memory_type: "summary",
            status: "active"
          )
          Memory.create!(
            account: @account,
            space: @space,
            title: "Knowledge Base",
            content: "This is knowledge",
            memory_type: "knowledge",
            status: "active"
          )

          result = @tool.execute(
            { query: "this", memory_type: "summary" },
            { space: @space }
          )

          assert result[:success]
          assert_equal 1, result[:count]
          assert_equal "summary", result[:memory_type]
          assert_equal "Space Summary", result[:memories].first[:title]
        end

        test "execute limits results" do
          # Create many memories
          15.times do |i|
            Memory.create!(
              account: @account,
              space: @space,
              title: "Memory #{i}",
              content: "Content #{i}",
              memory_type: "knowledge",
              status: "active"
            )
          end

          # Default limit (5)
          result = @tool.execute({ query: "Memory" }, { space: @space })
          assert result[:memories].length <= 5

          # Custom limit
          result = @tool.execute({ query: "Memory", limit: 8 }, { space: @space })
          assert result[:memories].length <= 8

          # Max limit enforced (10)
          result = @tool.execute({ query: "Memory", limit: 20 }, { space: @space })
          assert result[:memories].length <= 10
        end

        test "execute returns empty result when no matches" do
          result = @tool.execute({ query: "nonexistentxyz123" }, { space: @space })

          assert result[:success]
          assert_empty result[:memories]
          assert result[:message].include?("No memories found")
        end

        test "execute handles invalid memory_type gracefully" do
          Memory.create!(
            account: @account,
            space: @space,
            title: "Test ABC123",
            content: "Content",
            memory_type: "knowledge",
            status: "active"
          )

          # Invalid memory_type should be ignored, not cause error
          result = @tool.execute(
            { query: "ABC123", memory_type: "invalid_type" },
            { space: @space }
          )

          # Should still find the memory since type filter is invalid
          assert result[:success]
          assert result[:count] >= 1
          assert result[:memories].any? { |m| m[:title].include?("ABC123") }
        end

        test "execute formats memory data correctly" do
          user = @account.users.first || @account.users.create!(email: "test_mem@example.com", password: "password123")
          memory = Memory.create!(
            account: @account,
            space: @space,
            title: "Important Memory",
            content: "This is a very long content that should be truncated properly for the preview..." + ("x" * 500),
            memory_type: "knowledge",
            status: "active",
            created_by: user
          )

          result = @tool.execute({ query: "Important" }, { space: @space })

          assert result[:success]
          memory_data = result[:memories].first

          assert_equal memory.id, memory_data[:id]
          assert_equal "Important Memory", memory_data[:title]
          assert_equal "knowledge", memory_data[:type]
          assert_equal "active", memory_data[:status]
          assert memory_data[:preview].length <= 250  # Truncated
          assert memory_data[:updated_at].present?
          assert memory_data[:created_by].present?
        end

        test "execute handles database errors gracefully" do
          # Mock a database error
          mock_scope = mock()
          mock_scope.stubs(:active).raises(StandardError, "Database connection lost")

          mock_space = mock()
          mock_space.stubs(:memories).returns(mock_scope)

          error = assert_raises(StandardError) do
            @tool.execute({ query: "test" }, { space: mock_space })
          end

          assert_match(/Database connection lost/, error.message)
        end
      end
    end
  end
end
