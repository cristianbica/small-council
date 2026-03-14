# frozen_string_literal: true

module AI
  module Runtimes
    class BrainstormingConversationRuntime < ConversationRuntime
      DEFAULT_SOFT_LIMIT = 5
      DEFAULT_HARD_LIMIT = 15

      def advisor_responded(message)
        advisors = advisors_to_respond(message)
        return schedule_advisors_responses(advisors, message) if advisors.any?

        super
      end

      def user_posted(message)
        advisors = advisors_to_respond(message)
        return schedule_advisors_responses(advisors, message) if advisors.any? && !advisors.all(&:scribe?)

        request_scribe_response(prompt: :brainstorming_moderator)
      end

      def message_resolved(message)
        return handle_compaction_complete(message) if message.compaction?
        return unless message.from_scribe?

        return request_message_compaction(message) if compaction_required?

        if scribe_round_count >= DEFAULT_HARD_LIMIT
          request_scribe_response(prompt: :force_synthesis)
        else
          request_scribe_response(prompt: :brainstorming_moderator)
        end
      end

      protected

      def advisors_to_respond(message)
        # Compaction messages are summaries, never requests for responses
        return [] if message.compaction?

        return conversation.advisors.non_scribes if message.mentions_all? && (message.from_user? || message.from_scribe?)
        return [] unless message.mentions.any? && (message.from_user? || message.from_scribe?)
        conversation.advisors.where(name: message.mentions)
      end

      private

      def scribe_round_count
        conversation.messages.root_messages.complete.count(&:from_scribe?)
      end
    end
  end
end
