# frozen_string_literal: true

module AI
  module Handlers
    # Handles advisor/scribe response generation results
    #
    # Called after AI::Runner completes response generation
    # Updates the message state and notifies runtime sequencing.
    #
    class ConversationResponseHandler < BaseHandler
      MAX_AUTO_RETRIES = 2

      def handle(result)
        message = context.message
        conversation = context.conversation
        runtime = AI.runtime_for_conversation(conversation)

        if result.failure?
          handle_error(message, result, runtime)
        else
          message.update!(content: strip_speaker_prefix(result.content), status: "complete")
          runtime.advisor_responded(message)
        end
      end

      private

      def retry?(message)
        message.retry_count < MAX_AUTO_RETRIES
      end

      def handle_error(message, result, runtime)
        if retry?(message)
          message.update!(retry_count: message.retry_count + 1)
          Rails.logger.info("[AI Retry] Auto-retrying message #{message.id} for advisor #{message.sender.name} (attempt #{message.retry_count}/#{MAX_AUTO_RETRIES})")
          message.retry!(reset_retry_count: false)
        else
          error_msg = result.content.presence || "Error: #{result.error&.message || 'Unknown error'}"
          Rails.logger.error("[AI Error] Message #{message.id} failed after #{MAX_AUTO_RETRIES} retries: #{error_msg}")
          message.update!(
            content: strip_speaker_prefix(error_msg),
            status: :error
          )
          runtime.advisor_responded(message)
        end
      end

      def strip_speaker_prefix(content)
        normalized = content.to_s.lstrip
        stripped = normalized.gsub(/\A(?:\[speaker:\s*[^\]]+\]\s*)+/i, "")
        stripped.presence || content
      end
    end
  end
end
