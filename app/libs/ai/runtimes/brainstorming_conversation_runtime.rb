# frozen_string_literal: true

module AI
  module Runtimes
    class BrainstormingConversationRuntime < ConversationRuntime
      DEFAULT_SOFT_LIMIT = 5
      DEFAULT_HARD_LIMIT = 15

      def user_posted(message)
        advisors = advisors_to_respond(message)
        return schedule_advisors_responses(advisors, message) if advisors.any?

        request_scribe_response(prompt: :brainstorming_moderator)
      end

      def message_resolved(message)
        return unless message.from_scribe?

        if scribe_round_count >= DEFAULT_HARD_LIMIT
          request_scribe_response(prompt: :force_synthesis)
        else
          request_scribe_response(prompt: :brainstorming_moderator)
        end
      end

      protected

      def advisors_to_respond(message)
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
