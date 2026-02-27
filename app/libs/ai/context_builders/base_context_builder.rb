# frozen_string_literal: true

module AI
  module ContextBuilders
    # Base class for context builders - shared logic for building AI context
    #
    # Context builders encapsulate different strategies for building context
    # that gets passed to AI::Client. This separates context building from
    # the AI client itself, making both easier to test and reuse.
    #
    # Usage:
    #   builder = AI::ContextBuilders::ConversationContextBuilder.new(
    #     space, conversation, memory_limit: 10
    #   )
    #   context = builder.build
    #   # => { space: ..., conversation: ..., memories: [...], ... }
    #
    class BaseContextBuilder
      DEFAULT_MEMORY_LIMIT = 10
      DEFAULT_CONVERSATION_LIMIT = 5

      def initialize(space, conversation = nil, options = {})
        @space = space
        @conversation = conversation
        @options = options
      end

      # Build and return the context hash
      # Override in subclasses
      def build
        raise NotImplementedError, "#{self.class} must implement #build"
      end

      protected

      # Get recent memories from the space
      def recent_memories(limit: nil)
        limit ||= @options[:memory_limit] || DEFAULT_MEMORY_LIMIT
        return [] unless @space

        @space.memories.active.recent.limit(limit)
      end

      # Get recent conversations from the space (excluding current if present)
      def recent_conversations(limit: nil)
        limit ||= @options[:conversation_limit] || DEFAULT_CONVERSATION_LIMIT
        return [] unless @space

        scope = @space.conversations.recent
        scope = scope.where.not(id: @conversation.id) if @conversation
        scope.limit(limit)
      end

      # Get space advisors (excluding scribe)
      def space_advisors
        return [] unless @space

        @space.advisors.where.not("LOWER(name) LIKE ? OR LOWER(name) LIKE ?", "%scribe%", "%scrib%")
      end

      # Get the primary summary memory for the space
      def primary_summary
        return nil unless @space

        Memory.primary_summary_for(@space)
      end

      # Get council from conversation
      def council
        @conversation&.council
      end

      # Validate that required objects are present
      def validate_space!
        raise ArgumentError, "Space is required" unless @space
      end

      def validate_conversation!
        raise ArgumentError, "Conversation is required" unless @conversation
      end
    end
  end
end
