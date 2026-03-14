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

      test "advisor_responded schedules advisors for scribe root mentions" do
        message = messages(:consensus_round1)
        message.stubs(:mentions_all?).returns(false)
        message.stubs(:mentions).returns([ "fixture-counselor-one" ])
        message.stubs(:from_scribe?).returns(true)
        message.stubs(:from_user?).returns(false)

        advisor = advisors(:one)
        @conversation.advisors.stubs(:where).with(name: [ "fixture-counselor-one" ]).returns([ advisor ])

        @runtime.expects(:schedule_advisors_responses).with([ advisor ], message)

        @runtime.advisor_responded(message)
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

      test "message_resolved requests compaction when from scribe and over threshold" do
        message = messages(:consensus_round1)
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

      test "message_resolved continues to force_conclusion when under threshold but at hard limit" do
        message = messages(:consensus_round1)
        message.stubs(:from_scribe?).returns(true)
        message.stubs(:compaction?).returns(false)
        @runtime.stubs(:scribe_round_count).returns(15)
        @runtime.stubs(:compaction_required?).returns(false)

        @runtime.expects(:request_message_compaction).never
        @runtime.expects(:request_scribe_response).with(prompt: :force_conclusion)

        @runtime.message_resolved(message)
      end

      test "compaction message triggers handle_compaction_complete instead of normal flow" do
        scribe = advisors(:'scribe-space-one')
        message = messages(:consensus_user_topic)

        compaction_msg = @conversation.messages.create!(
          account: @account,
          sender: scribe,
          role: "advisor",
          content: "Compacted",
          status: "complete",
          message_type: "compaction",
          metadata: { compaction_for_message_id: message.id }
        )

        @runtime.expects(:handle_compaction_complete).with(compaction_msg)

        @runtime.message_resolved(compaction_msg)
      end

      test "compaction messages do not trigger advisor responses through advisors_to_respond" do
        # Ensure scribe is present
        @conversation.ensure_scribe_present!
        scribe = @conversation.scribe_advisor

        # Create a compaction message with @mentions in content
        compaction_msg = @conversation.messages.create!(
          account: @account,
          sender: scribe,
          role: "advisor",
          content: "Summary of input from @fixture-counselor-one and @fixture-counselor-two",
          status: "complete",
          message_type: "compaction"
        )

        # Verify advisors_to_respond returns empty for compaction messages
        # even if they contain @mentions
        result = @runtime.send(:advisors_to_respond, compaction_msg)
        assert_empty result, "Compaction messages should not trigger any advisor responses"
      end
    end
  end
end
