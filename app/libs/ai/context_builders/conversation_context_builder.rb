# frozen_string_literal: true


module AI
  module ContextBuilders
    # Builds context for advisors responding in conversations
    #
    # This context includes:
    # - Space context (memories, advisors)
    # - Current conversation details
    # - User information
    # - Related conversations for context
    # - Council information
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
        validate_space!
        validate_conversation!

        {
          space: @space,
          conversation: @conversation,
          user: @conversation.user,
          council: council,
          memories: recent_memories,
          related_conversations: recent_conversations,
          advisors: space_advisors,
          primary_summary: primary_summary,
          account: @space.account
        }.compact
      end
    end
  end
end
