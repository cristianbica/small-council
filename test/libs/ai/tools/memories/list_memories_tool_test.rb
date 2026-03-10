# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Memories
      class ListMemoriesToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          @context = { space: @space, user: @user }

          # Create some test memories
          @memory1 = @space.memories.create!(
            account: @account,
            title: "Memory 1",
            content: "Content 1",
            memory_type: "knowledge",
            created_by: @user,
            updated_by: @user
          )
          @memory2 = @space.memories.create!(
            account: @account,
            title: "Memory 2",
            content: "Content 2",
            memory_type: "summary",
            created_by: @user,
            updated_by: @user
          )
        end

        test "read_only is true" do
          assert_equal true, ListMemoriesTool.read_only
        end

        test "requires_approval is false" do
          assert_equal false, ListMemoriesTool.requires_approval
        end

        test "execute returns paginated memories" do
          tool = ListMemoriesTool.new(@context)

          result = tool.execute

          assert result[:success]
          assert result[:memories].length >= 2
          assert result[:total_count] >= 2
          assert_equal 10, result[:limit]
          assert_equal 0, result[:offset]
        end

        test "execute filters by memory_type" do
          tool = ListMemoriesTool.new(@context)

          result = tool.execute(memory_type: "knowledge")

          assert result[:success]
          assert result[:memories].all? { |m| m[:type] == "knowledge" }
        end

        test "execute respects limit" do
          tool = ListMemoriesTool.new(@context)

          result = tool.execute(limit: 1)

          assert result[:success]
          assert_equal 1, result[:count]
          assert_equal 1, result[:limit]
        end

        test "execute enforces max limit of 20" do
          tool = ListMemoriesTool.new(@context)

          result = tool.execute(limit: 50)

          assert result[:success]
          assert_equal 20, result[:limit]
        end

        test "execute enforces min limit of 10" do
          tool = ListMemoriesTool.new(@context)

          result = tool.execute(limit: 0)

          assert result[:success]
          assert_equal 10, result[:limit]
        end

        test "execute with offset" do
          tool = ListMemoriesTool.new(@context)

          result = tool.execute(offset: 1)

          assert result[:success]
          assert_equal 1, result[:offset]
        end

        test "has_more is false when all results shown" do
          tool = ListMemoriesTool.new(@context)

          result = tool.execute(limit: 100)

          assert result[:success]
          assert_equal false, result[:has_more]
        end
      end
    end
  end
end
