# frozen_string_literal: true

module AI
  module Handlers
    # Handles advisor/scribe response generation results
    #
    # Called after AI::Runner completes response generation
    # Updates the message state and notifies runtime sequencing.
    #
    class ConversationResponseHandler < BaseHandler
      def handle(result)
        message = context.message
        conversation = context.conversation
        runtime = AI.runtime_for_conversation(conversation)

        message.update!(
          content: strip_speaker_prefix(result.content.presence || "Error: Empty response from AI"),
          status: result.failure? ? "error" : "complete"
        )
        runtime.advisor_responded(message)
      end

      private

      def strip_speaker_prefix(content)
        normalized = content.to_s.lstrip
        stripped = normalized.gsub(/\A(?:\[speaker:\s*[^\]]+\]\s*)+/i, "")
        stripped.presence || content
      end
    end
  end
end
