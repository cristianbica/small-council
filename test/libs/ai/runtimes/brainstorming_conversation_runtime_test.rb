# frozen_string_literal: true

require "test_helper"

module AI
  module Runtimes
    class BrainstormingConversationRuntimeTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:brainstorming)
        @runtime = BrainstormingConversationRuntime.new(@conversation)
      end

      test "user_posted triggers scribe moderator when no mentions" do
        message = messages(:one)
        message.stubs(:mentions).returns([])

        @runtime.expects(:schedule_advisors_responses).never
        @runtime.expects(:request_scribe_response).with(prompt: :brainstorming_moderator)

        @runtime.user_posted(message)
      end

      test "message_resolved triggers scribe with force_synthesis at hard limit" do
        message = messages(:one)
        message.stubs(:from_scribe?).returns(true)

        @runtime.stubs(:scribe_round_count).returns(15)

        @runtime.expects(:request_scribe_response).with(prompt: :force_synthesis)

        @runtime.message_resolved(message)
      end

      test "advisor_responded schedules advisors for scribe root mentions" do
        message = messages(:one)
        message.stubs(:mentions_all?).returns(false)
        message.stubs(:mentions).returns([ "fixture-counselor-one" ])
        message.stubs(:from_scribe?).returns(true)
        message.stubs(:from_user?).returns(false)

        advisor = advisors(:one)
        @conversation.advisors.stubs(:where).with(name: [ "fixture-counselor-one" ]).returns([ advisor ])

        @runtime.expects(:schedule_advisors_responses).with([ advisor ], message)

        @runtime.advisor_responded(message)
      end

      test "message_resolved requests compaction when from scribe and over threshold" do
        message = messages(:one)
        message.stubs(:from_scribe?).returns(true)
        message.stubs(:compaction?).returns(false)

        # Create many messages to exceed threshold
        10.times do
          @conversation.messages.create!(
            account: @account,
            sender: @conversation.user,
            role: "user",
            content: "x" * 3000,
            status: "complete"
          )
        end

        @runtime.expects(:request_message_compaction).once

        @runtime.message_resolved(message)
      end

      test "message_resolved continues to force_synthesis when under threshold but at hard limit" do
        message = messages(:one)
        message.stubs(:from_scribe?).returns(true)
        message.stubs(:compaction?).returns(false)
        @runtime.stubs(:scribe_round_count).returns(15)
        @runtime.stubs(:compaction_required?).returns(false)

        @runtime.expects(:request_message_compaction).never
        @runtime.expects(:request_scribe_response).with(prompt: :force_synthesis)

        @runtime.message_resolved(message)
      end
    end
  end
end
