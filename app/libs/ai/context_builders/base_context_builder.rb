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

      # Get space advisors (excluding scribe using is_scribe flag)
      def space_advisors
        return [] unless @space

        @space.advisors.where(is_scribe: false)
      end

      # Get conversation participants (advisors only, not scribe)
      def conversation_advisors
        return [] unless @conversation

        @conversation.participant_advisors
      end

      # Get the primary summary memory for the space
      def primary_summary
        return nil unless @space

        Memory.primary_summary_for(@space)
      end

      # Get space from conversation (for adhoc) or council
      def effective_space
        return @space if @space
        return @conversation.council.space if @conversation&.council_meeting?
        nil
      end

      # Build conversation thread context for message threading
      def conversation_thread
        return [] unless @conversation

        @conversation.messages.root_messages.chronological.map do |msg|
          {
            role: msg.role == "advisor" ? "assistant" : msg.role,
            content: msg.content,
            sender_name: sender_display_name(msg.sender),
            message_id: msg.id,
            replies: msg.replies.chronological.map do |reply|
              {
                role: reply.role == "advisor" ? "assistant" : reply.role,
                content: reply.content,
                sender_name: sender_display_name(reply.sender),
                parent_id: reply.in_reply_to_id
              }
            end
          }
        end
      end

      def sender_display_name(sender)
        return sender.display_name if sender.respond_to?(:display_name)
        return sender.name if sender.respond_to?(:name)

        sender.to_s
      end

      # Get conversation rules of engagement description
      def roe_description
        return nil unless @conversation

        case @conversation.roe_type
        when "open"
          "Advisors respond when @mentioned. Use @all to invite everyone. Max depth: 1."
        when "consensus"
          "All advisors discuss until reaching agreement. Max depth: 2."
        when "brainstorming"
          "All advisors contribute ideas iteratively. Max depth: 2."
        else
          "Unknown engagement mode."
        end
      end

      def validate_conversation!
        raise ArgumentError, "Conversation is required" unless @conversation
      end
    end
  end
end
