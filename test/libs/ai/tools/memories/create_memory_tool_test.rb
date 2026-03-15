# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Memories
      class CreateMemoryToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          @context = { space: @space, user: @user, account: @account }
        end

        test "requires_approval is true" do
          assert_equal true, CreateMemoryTool.requires_approval
        end

        test "read_only is false" do
          assert_equal false, CreateMemoryTool.read_only
        end

        test "execute creates a memory" do
          tool = CreateMemoryTool.new(@context)

          result = tool.execute(title: "Test Memory", content: "Test content")

          assert result[:success]
          assert result[:memory_id]
          assert_equal "Test Memory", result[:title]
          assert_equal "knowledge", result[:memory_type]

          memory = Memory.find(result[:memory_id])
          assert_equal "Test Memory", memory.title
          assert_equal "Test content", memory.content
          assert_equal @space, memory.space
          assert_equal @account, memory.account
        end

        test "execute with custom memory_type" do
          tool = CreateMemoryTool.new(@context)

          result = tool.execute(title: "Summary", content: "Summary content", memory_type: "summary")

          assert result[:success]
          assert_equal "summary", result[:memory_type]
        end

        test "execute falls back to knowledge for invalid memory_type" do
          tool = CreateMemoryTool.new(@context)

          result = tool.execute(title: "Test", content: "Content", memory_type: "invalid")

          assert result[:success]
          assert_equal "knowledge", result[:memory_type]
        end

        test "execute returns error for blank title" do
          tool = CreateMemoryTool.new(@context)

          result = tool.execute(title: "", content: "Content")

          assert_equal false, result[:success]
          assert_equal "title is required", result[:error]
        end

        test "execute returns error for blank content" do
          tool = CreateMemoryTool.new(@context)

          result = tool.execute(title: "Title", content: "")

          assert_equal false, result[:success]
          assert_equal "content is required", result[:error]
        end

        test "execute returns error for nil title" do
          tool = CreateMemoryTool.new(@context)

          result = tool.execute(title: nil, content: "Content")

          assert_equal false, result[:success]
          assert_equal "title is required", result[:error]
        end

        test "execute returns error for nil content" do
          tool = CreateMemoryTool.new(@context)

          result = tool.execute(title: "Title", content: nil)

          assert_equal false, result[:success]
          assert_equal "content is required", result[:error]
        end

        test "tool name is present" do
          tool = CreateMemoryTool.new(@context)
          assert tool.name.present?
        end
      end
    end
  end
end
