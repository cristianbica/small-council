# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Memories
      class SearchMemoriesToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          @memory1 = @space.memories.create!(
            account: @account,
            title: "Ruby Programming",
            content: "Ruby is a great language",
            memory_type: "knowledge",
            created_by: @user,
            updated_by: @user
          )
          @memory2 = @space.memories.create!(
            account: @account,
            title: "Rails Framework",
            content: "Rails makes web development easy",
            memory_type: "knowledge",
            created_by: @user,
            updated_by: @user
          )
          @memory3 = @space.memories.create!(
            account: @account,
            title: "Python Guide",
            content: "Python for data science",
            memory_type: "summary",
            created_by: @user,
            updated_by: @user
          )
          @context = { space: @space, user: @user }
        end

        test "read_only is true" do
          assert_equal true, SearchMemoriesTool.read_only
        end

        test "requires_approval is false" do
          assert_equal false, SearchMemoriesTool.requires_approval
        end

        test "execute searches by title" do
          tool = SearchMemoriesTool.new(@context)

          result = tool.execute(query: "Ruby")

          assert result[:success]
          assert result[:memories].any? { |m| m[:title] == "Ruby Programming" }
        end

        test "execute searches by content" do
          tool = SearchMemoriesTool.new(@context)

          result = tool.execute(query: "Python")

          assert result[:success]
          # Should find the Python Guide memory by title
          assert result[:memories].any? { |m| m[:title].include?("Python") }
        end

        test "execute filters by memory_type" do
          tool = SearchMemoriesTool.new(@context)

          result = tool.execute(query: "great", memory_type: "knowledge")

          assert result[:success]
          assert result[:memories].all? { |m| m[:type] == "knowledge" }
        end

        test "execute returns empty result for no matches" do
          tool = SearchMemoriesTool.new(@context)

          result = tool.execute(query: "nonexistentxyz123")

          assert result[:success]
          assert_empty result[:memories]
          assert result[:message].include?("No memories found")
        end

        test "execute returns error for blank query" do
          tool = SearchMemoriesTool.new(@context)

          result = tool.execute(query: "")

          assert_equal false, result[:success]
          assert result[:error].include?("required")
        end

        test "execute respects limit" do
          tool = SearchMemoriesTool.new(@context)

          result = tool.execute(query: "a", limit: 2)

          assert result[:success]
          assert_operator result[:memories].length, :<=, 2
        end

        test "execute enforces max limit of 10" do
          tool = SearchMemoriesTool.new(@context)

          result = tool.execute(query: "a", limit: 50)

          assert result[:success]
          assert_operator result[:count], :<=, 10
        end
      end
    end
  end
end
