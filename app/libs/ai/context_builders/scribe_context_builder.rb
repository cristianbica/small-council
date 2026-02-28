# frozen_string_literal: true


module AI
  module ContextBuilders
    # Builds context for Scribe chat mode
    #
    # This context includes:
    # - Space context (memories, advisors)
    # - User information
    # - Scribe advisor
    # - Recent conversations
    #
    # Unlike ConversationContextBuilder, this does NOT include a specific
    # conversation since Scribe mode operates at the space level.
    #
    # Usage:
    #   builder = AI::ContextBuilders::ScribeContextBuilder.new(
    #     @space,
    #     nil,
    #     user: Current.user,
    #     advisor: @scribe_advisor,
    #     memory_limit: 20
    #   )
    #   context = builder.build
    #
    class ScribeContextBuilder < BaseContextBuilder
      def build
        raise ArgumentError, "Space is required" unless @space

        ctx = {
          space: @space,
          user: @options[:user],
          advisor: @options[:advisor],
          memories: recent_memories,
          recent_conversations: recent_conversations,
          advisors: space_advisors,
          primary_summary: primary_summary,
          account: @space.account
        }

        ctx.compact
      end
    end
  end
end
