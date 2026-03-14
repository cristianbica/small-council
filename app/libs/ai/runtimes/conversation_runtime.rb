# frozen_string_literal: true

module AI
  module Runtimes
    class ConversationRuntime
      attr_reader :conversation

      def initialize(conversation)
        @conversation = conversation
      end

      def user_posted(message)
        raise NotImplementedError, "#{self.class} must implement #user_posted"
      end

      def advisor_responded(message)
        return handle_compaction_complete(message) if message.compaction?
        return unless message.reply?

        message.parent_message.resolve_for_advisor!(message.sender_id)
        request_next_advisor_response(message.parent_message) || message_resolved(message.parent_message)
      end

      def message_resolved(message)
        request_message_compaction(message) if message.from_scribe? && compaction_required?
      end

      protected

      def schedule_advisors_responses(advisors, parent_message)
        pending_messages = advisors.map do |advisor|
          @conversation.messages.create!(
            account: @conversation.account,
            sender: advisor,
            role: "advisor",
            parent_message: parent_message,
            content: "...",
            status: "pending"
          )
        end
        parent_message.update!(pending_advisor_ids: advisors.map(&:id)) if pending_messages.any?
        request_advisor_response(pending_messages.first) if pending_messages.any?
      end

      def request_next_advisor_response(parent_message)
        next_pending = parent_message.replies
          .where(sender_type: "Advisor", status: "pending")
          .order(:created_at)
          .first
        return false unless next_pending
        request_advisor_response(next_pending)
      end

      def request_advisor_response(message)
        AI.generate_advisor_response(
          advisor: message.sender,
          message: message,
          prompt: nil,
          async: true
        )
      end

      def request_scribe_response(message: nil, prompt: nil)
        scribe = conversation.advisors.find(&:scribe?)
        return unless scribe

        pending_message = @conversation.messages.create!(
          account: @conversation.account,
          sender: scribe,
          role: "advisor",
          parent_message: message,
          content: "...",
          status: "pending"
        )

        AI.generate_advisor_response(
          advisor: scribe,
          message: pending_message,
          prompt: prompt.present? ? "conversations/#{prompt}" : nil,
          async: true
        )
      end

      COMPACTION_THRESHOLD = 25_000

      def compaction_required?
        current_context_length = @conversation.messages.since_last_compaction.pluck(:content).join.length
        Rails.logger.info("\n\n########################### Current context length: #{current_context_length}\n\n")
        current_context_length > COMPACTION_THRESHOLD
      end

      def request_message_compaction(message)
        compaction_message = @conversation.messages.create!(
          account: @conversation.account,
          sender: @conversation.scribe_advisor,
          role: "advisor",
          content: "...",
          message_type: "compaction",
          status: "pending",
          metadata: { compaction_for_message_id: message.id }
        )
        AI.compact_conversation(message: compaction_message, tracker: :model_interaction, async: true)
      end

      def handle_compaction_complete(message)
        return unless message.complete?

        original_message_id = message.metadata["compaction_for_message_id"]
        original_message = @conversation.messages.find_by(id: original_message_id)
        return unless original_message

        message_resolved(original_message)
      end
    end
  end
end
