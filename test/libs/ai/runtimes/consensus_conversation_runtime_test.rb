# frozen_string_literal: true

require "test_helper"

module AI
  module Runtimes
    class ConsensusConversationRuntimeTest < ActiveSupport::TestCase
      setup do
        @account = accounts(:one)
        set_tenant(@account)
        @conversation = conversations(:consensus)
        @runtime = ConsensusConversationRuntime.new(@conversation)
      end

      test "user_posted triggers scribe when no mentions" do
        message = messages(:consensus_user_topic)
        message.stubs(:mentions).returns([])

        @runtime.expects(:schedule_advisors_responses).never
        @runtime.expects(:request_scribe_response).with(prompt: :consensus_moderator)

        @runtime.user_posted(message)
      end

      test "message_resolved triggers scribe with force_conclusion at hard limit" do
        message = messages(:consensus_round1)
        message.stubs(:from_scribe?).returns(true)

        @runtime.stubs(:scribe_round_count).returns(15)

        @runtime.expects(:request_scribe_response).with(prompt: :force_conclusion)

        @runtime.message_resolved(message)
      end

      test "message_resolved triggers scribe with moderator before hard limit" do
        message = messages(:consensus_round1)
        message.stubs(:from_scribe?).returns(true)

        @runtime.stubs(:scribe_round_count).returns(5)

        @runtime.expects(:request_scribe_response).with(prompt: :consensus_moderator)

        @runtime.message_resolved(message)
      end

      test "scribe_round_count counts completed scribe root messages" do
        # Create a scribe advisor
        scribe = @account.advisors.create!(
          name: "test-scribe",
          system_prompt: "You are the scribe",
          is_scribe: true
        )

        # The consensus fixture already has 1 advisor message (consensus_round1)
        initial_count = @runtime.send(:scribe_round_count)

        3.times do
          @conversation.messages.create!(
            account: @account,
            sender: scribe,
            role: "advisor",
            content: "Round summary",
            status: "complete"
          )
        end

        count = @runtime.send(:scribe_round_count)

        assert_equal initial_count + 3, count
      end
    end
  end
end
