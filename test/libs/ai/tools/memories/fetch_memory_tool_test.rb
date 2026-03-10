# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Memories
      class FetchMemoryToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          @memory = @space.memories.create!(
            account: @account,
            title: "Test Memory",
            content: "Test content",
            memory_type: "knowledge",
            created_by: @user,
            updated_by: @user
          )
          @context = { space: @space, user: @user }
        end

        test "read_only is true" do
          assert_equal true, FetchMemoryTool.read_only
        end

        test "requires_approval is false" do
          assert_equal false, FetchMemoryTool.requires_approval
        end

        test "execute returns memory details" do
          tool = FetchMemoryTool.new(@context)

          result = tool.execute(memory_id: @memory.id)

          assert result[:success]
          assert_equal @memory.id, result[:memory][:id]
          assert_equal "Test Memory", result[:memory][:title]
          assert_equal "Test content", result[:memory][:content]
          assert_equal "knowledge", result[:memory][:type]
        end

        test "execute returns error for blank memory_id" do
          tool = FetchMemoryTool.new(@context)

          result = tool.execute(memory_id: nil)

          assert_equal false, result[:success]
          assert result[:error].include?("required")
        end

        test "execute returns error for non-existent memory" do
          tool = FetchMemoryTool.new(@context)

          result = tool.execute(memory_id: 99999)

          assert_equal false, result[:success]
          assert result[:error].include?("not found")
        end
      end
    end
  end
end
