# frozen_string_literal: true

require "test_helper"

module AI
  module Trackers
    class VersionsTrackerTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @space = spaces(:one)
        @advisor = advisors(:one)
        @context = AI::Contexts::ConversationContext.new(
          conversation: conversations(:one),
          advisor: @advisor,
          account: @account
        )
        @tracker = VersionsTracker.new(context: @context)
      end

      test "initialize stores task and context" do
        task = mock("task")
        tracker = VersionsTracker.new(task: task, context: @context)

        assert_equal task, tracker.task
        assert_equal @context, tracker.context
      end

      test "track is a no-op and returns nil" do
        result = AI::Result.new
        # Should not raise or do anything
        return_value = @tracker.track(result)
        assert_nil return_value
      end

      test "register sets up before_tool_call and after_tool_call callbacks" do
        chat = Object.new
        before_block = nil
        after_block = nil

        chat.define_singleton_method(:before_tool_call) { |&block| before_block = block }
        chat.define_singleton_method(:after_tool_call) { |&block| after_block = block }

        @tracker.register(chat)

        assert before_block.is_a?(Proc), "before_tool_call should have registered a block"
        assert after_block.is_a?(Proc), "after_tool_call should have registered a block"
      end

      test "write_tool? returns true for non-read-only tools" do
        # memories/create is not read-only
        assert @tracker.send(:write_tool?, "memories/create")
      end

      test "write_tool? returns false for read-only tools" do
        # memories/list is read-only
        assert_not @tracker.send(:write_tool?, "memories/list")
      end

      test "write_tool? returns false for unknown tools" do
        assert_not @tracker.send(:write_tool?, "unknown/tool")
      end

      test "write_tool? handles ResolutionError gracefully" do
        AI.expects(:tool).raises(AI::ResolutionError, "Unknown tool")
        assert_not @tracker.send(:write_tool?, "bad/tool")
      end
    end
  end
end
