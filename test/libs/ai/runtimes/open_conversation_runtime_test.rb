# frozen_string_literal: true

require "test_helper"

module AI
  module Runtimes
    class OpenConversationRuntimeTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:one)
        @runtime = OpenConversationRuntime.new(@conversation)
      end

      test "user_posted schedules mentioned advisors" do
        message = messages(:one)
        message.stubs(:mentions_all?).returns(false)
        message.stubs(:mentions).returns([ "one" ])

        advisor = advisors(:one)
        @conversation.advisors.stubs(:where).with(name: [ "one" ]).returns([ advisor ])

        @runtime.expects(:schedule_advisors_responses).with([ advisor ], message)

        @runtime.user_posted(message)
      end

      test "user_posted schedules all non-scribes when @all mentioned" do
        message = messages(:one)
        message.stubs(:mentions_all?).returns(true)

        non_scribes = @conversation.advisors.reject(&:scribe?)
        @conversation.advisors.stubs(:non_scribes).returns(non_scribes)

        @runtime.expects(:schedule_advisors_responses).with(non_scribes, message)

        @runtime.user_posted(message)
      end

      test "user_posted does nothing when no advisors to respond" do
        message = messages(:one)
        message.stubs(:mentions_all?).returns(false)
        message.stubs(:mentions).returns([])

        @conversation.stubs(:participant_advisors).returns([])

        @runtime.expects(:schedule_advisors_responses).never

        @runtime.user_posted(message)
      end
    end
  end
end
