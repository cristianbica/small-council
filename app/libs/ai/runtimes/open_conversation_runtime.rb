# frozen_string_literal: true

module AI
  module Runtimes
    class OpenConversationRuntime < ConversationRuntime
      def user_posted(message)
        advisors = advisors_to_respond(message)
        schedule_advisors_responses(advisors, message) if advisors.any?
      end

      protected
      def advisors_to_respond(message)
        # Compaction messages are summaries, never requests for responses
        return [] if message.compaction?

        return conversation.advisors.non_scribes if message.mentions_all?
        return conversation.advisors if conversation.advisors.size == 1

        conversation.advisors.where(name: message.mentions)
      end
    end
  end
end
