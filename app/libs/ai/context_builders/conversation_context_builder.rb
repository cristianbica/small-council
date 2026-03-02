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
      MEMORY_INDEX_KNOWLEDGE_LIMIT = 8
      MEMORY_INDEX_EXCERPT_WORD_LIMIT = 50

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
          memory_index: memory_index,
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

      def memory_index
        index = {
          primary_summary: memory_index_primary_summary,
          knowledge_entries: memory_index_knowledge_entries
        }

        index.compact
      end

      def memory_index_primary_summary
        summary = effective_space&.memories&.active&.summary_type&.recent&.first
        return nil unless summary&.active?

        {
          id: summary.id,
          title: summary.title,
          summary_excerpt_50_words: summary_excerpt_50_words(summary.content)
        }
      end

      def memory_index_knowledge_entries
        effective_space&.memories
          &.active
          &.knowledge
          &.recent
          &.limit(MEMORY_INDEX_KNOWLEDGE_LIMIT)
          &.map do |memory|
            {
              id: memory.id,
              title: memory.title,
              summary_excerpt_50_words: summary_excerpt_50_words(memory.content)
            }
          end || []
      end

      def summary_excerpt_50_words(content)
        normalized = content.to_s.gsub(/\s+/, " ").strip
        return "" if normalized.empty?

        normalized.split(" ").first(MEMORY_INDEX_EXCERPT_WORD_LIMIT).join(" ")
      end
    end
  end
end
