# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Internal
      class ListMemoriesToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = @account.users.first || @account.users.create!(email: "test@example.com", password: "password123")
          @tool = ListMemoriesTool.new

          # Clear existing memories from fixtures to get predictable counts
          @space.memories.destroy_all

          # Create test memories
          5.times do |i|
            @space.memories.create!(
              account: @account,
              title: "Memory #{i + 1}",
              content: "Content for memory #{i + 1}",
              memory_type: i.even? ? "knowledge" : "summary",
              status: "active",
              created_by: @user
            )
          end

          # Create an archived memory (should not appear in results)
          @space.memories.create!(
            account: @account,
            title: "Archived Memory",
            content: "This is archived",
            memory_type: "knowledge",
            status: "archived",
            created_by: @user
          )
        end

        test "name returns list_memories" do
          assert_equal "list_memories", @tool.name
        end

        test "description is present" do
          assert @tool.description.present?
          assert @tool.description.include?("List")
        end

        test "parameters schema is valid" do
          params = @tool.parameters
          assert_equal "object", params[:type]
          assert params[:properties].key?(:memory_type)
          assert params[:properties].key?(:limit)
          assert params[:properties].key?(:offset)
          assert_empty params[:required]
        end

        test "execute returns error without context" do
          error = assert_raises(ArgumentError) do
            @tool.execute({}, {})
          end
          assert_match(/Missing required context: space/, error.message)
        end

        test "execute lists active memories" do
          result = @tool.execute({}, { space: @space })

          assert result[:success]
          assert_equal 5, result[:count]
          assert_equal 5, result[:total_count]
          assert result[:memories].all? { |m| m[:status] == "active" }
          assert_not result[:memories].any? { |m| m[:title] == "Archived Memory" }
        end

        test "execute filters by memory_type" do
          result = @tool.execute({ memory_type: "summary" }, { space: @space })

          assert result[:success]
          assert_equal 2, result[:count]  # Memories 2 and 4
          assert result[:memories].all? { |m| m[:type] == "summary" }
        end

        test "execute filters by knowledge type" do
          result = @tool.execute({ memory_type: "knowledge" }, { space: @space })

          assert result[:success]
          assert_equal 3, result[:count]  # Memories 1, 3, and 5
          assert result[:memories].all? { |m| m[:type] == "knowledge" }
        end

        test "execute ignores invalid memory_type filter" do
          result = @tool.execute({ memory_type: "invalid" }, { space: @space })

          assert result[:success]
          assert_equal 5, result[:count]  # Returns all active memories
        end

        test "execute respects limit parameter" do
          result = @tool.execute({ limit: 3 }, { space: @space })

          assert result[:success]
          assert_equal 3, result[:count]
          assert_equal 3, result[:limit]
        end

        test "execute enforces max limit" do
          result = @tool.execute({ limit: 50 }, { space: @space })

          assert result[:success]
          assert result[:limit] <= 20
          assert result[:count] <= 20
        end

        test "execute enforces min limit" do
          result = @tool.execute({ limit: 0 }, { space: @space })

          assert result[:success]
          assert_equal 10, result[:limit]
        end

        test "execute respects offset for pagination" do
          result = @tool.execute({ limit: 2, offset: 2 }, { space: @space })

          assert result[:success]
          assert_equal 2, result[:count]
          assert_equal 2, result[:offset]
        end

        test "execute returns has_more when more results available" do
          result = @tool.execute({ limit: 2 }, { space: @space })

          assert result[:success]
          assert result[:has_more]
          assert_equal 5, result[:total_count]
          assert_equal 2, result[:count]
        end

        test "execute returns has_more false when no more results" do
          result = @tool.execute({ limit: 10 }, { space: @space })

          assert result[:success]
          assert_not result[:has_more]
        end

        test "execute formats memory data correctly" do
          result = @tool.execute({ limit: 1 }, { space: @space })

          memory = result[:memories].first
          assert memory[:id].present?
          assert memory[:title].present?
          assert memory[:type].present?
          assert memory[:status].present?
          assert memory[:preview].present?
          assert memory[:updated_at].present?
        end

        test "execute returns empty results for empty space" do
          empty_space = @account.spaces.create!(name: "Empty Space")

          result = @tool.execute({}, { space: empty_space })

          assert result[:success]
          assert_equal 0, result[:count]
          assert_empty result[:memories]
        end
      end
    end
  end
end
