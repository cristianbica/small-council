# frozen_string_literal: true

module AI
  module ContextBuilders
    # Builds context for advisors responding in conversations
    #
    # This context includes:
    # - Space context (memories, advisors)
    # - Current conversation details with threaded messages
    # - Participant list (advisors in the conversation)
    # - User information
    # - Rules of Engagement description
    #
    # Usage:
    #   builder = AI::ContextBuilders::ConversationContextBuilder.new(
    #     conversation.space,
    #     conversation,
    #     memory_limit: 10,
    #     conversation_limit: 3
    #   )
    #   context = builder.build
    #
    class ConversationContextBuilder < BaseContextBuilder
      def build
        validate_conversation!
        validate_space!

        ctx = {
          space: effective_space,
          conversation: @conversation,
          user: @conversation.user,
          participants: conversation_participants_list,
          scribe: scribe_info,
          memories: recent_memories,
          primary_summary: primary_summary,
          related_conversations: recent_conversations,
          advisors: conversation_advisors,
          available_advisors: space_advisors,
          conversation_thread: conversation_thread,
          roe_type: @conversation.roe_type,
          roe_description: roe_description,
          max_depth: @conversation.max_depth,
          account: @conversation.account
        }

        # Add council info if council meeting
        if @conversation.council_meeting? && @conversation.council
          ctx[:council] = @conversation.council
        end

        ctx.compact
      end

      private

      def conversation_participants_list
        @conversation.conversation_participants.ordered.map do |participant|
          {
            id: participant.advisor_id,
            name: participant.advisor.name,
            role: participant.role,
            is_scribe: participant.scribe?
          }
        end
      end

      def scribe_info
        scribe = @conversation.scribe_advisor
        return nil unless scribe

        {
          id: scribe.id,
          name: scribe.name,
          is_present: true
        }
      end

      def validate_space!
        # Space can be passed directly or extracted from conversation's council
        return if @space
        return if @conversation&.council_meeting? && @conversation.council&.space
        raise ArgumentError, "Space is required"
      end
    end
  end
end
