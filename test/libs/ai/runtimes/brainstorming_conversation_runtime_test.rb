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
    end
  end
end
