# frozen_string_literal: true

require "test_helper"

module AI
  module Tools
    module Memories
      class UpdateMemoryToolTest < ActiveSupport::TestCase
        setup do
          @account = accounts(:one)
          set_tenant(@account)
          @space = spaces(:one)
          @user = users(:one)
          @memory = @space.memories.create!(
            account: @account,
            title: "Original Title",
            content: "Original content",
            memory_type: "knowledge",
            created_by: @user,
            updated_by: @user
          )
          @context = { space: @space, user: @user, account: @account }
        end

        test "requires_approval is true" do
          assert_equal true, UpdateMemoryTool.requires_approval
        end

        test "read_only is false" do
          assert_equal false, UpdateMemoryTool.read_only
        end

        test "execute updates title" do
          tool = UpdateMemoryTool.new(@context)

          result = tool.execute(memory_id: @memory.id, title: "New Title")

          assert result[:success]
          assert_equal "New Title", result[:title]
          @memory.reload
          assert_equal "New Title", @memory.title
        end

        test "execute updates content" do
          tool = UpdateMemoryTool.new(@context)

          result = tool.execute(memory_id: @memory.id, content: "New content")

          assert result[:success]
          @memory.reload
          assert_equal "New content", @memory.content
        end

        test "execute updates memory successfully" do
          tool = UpdateMemoryTool.new(@context)

          result = tool.execute(memory_id: @memory.id, title: "New Title")

          assert result[:success]
          assert_equal "New Title", result[:title]
          assert_equal "Memory updated successfully", result[:message]
        end

        test "execute raises ArgumentError for missing memory_id" do
          tool = UpdateMemoryTool.new(@context)

          assert_raises(ArgumentError) do
            tool.execute(title: "New Title")
          end
        end

        test "execute returns error for non-existent memory" do
          tool = UpdateMemoryTool.new(@context)

          result = tool.execute(memory_id: 99999, title: "New Title")

          assert_equal false, result[:success]
          assert result[:error].include?("not found")
        end

        test "execute returns error when no fields provided" do
          tool = UpdateMemoryTool.new(@context)

          result = tool.execute(memory_id: @memory.id)

          assert_equal false, result[:success]
          assert result[:error].include?("No fields to update")
        end

        test "execute handles invalid record" do
          tool = UpdateMemoryTool.new(@context)

          Memory.any_instance.stubs(:update!).raises(ActiveRecord::RecordInvalid.new(Memory.new))

          result = tool.execute(memory_id: @memory.id, title: "New")

          assert_equal false, result[:success]
          assert result[:error].include?("Failed to update")
        end

        test "tool name is present" do
          tool = UpdateMemoryTool.new(@context)
          assert tool.name.present?
        end
      end
    end
  end
end
