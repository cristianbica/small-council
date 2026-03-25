# frozen_string_literal: true

module AI
  module Commands
    class KickCommand < BaseCommand
      def validate
        if args.empty?
          errors << "Usage: /kick advisor-name"
          return
        end

        errors << "Please provide an advisor name like advisor-name" if normalized_advisor_name(args.first).blank?
      end

      def execute(conversation:, user:)
        advisor_name = normalized_advisor_name(args.first)

        return { success: false, message: "Conversation space is required" } if conversation.space_id.blank?

        advisor = conversation.account.advisors.find_by(space_id: conversation.space_id, name: advisor_name)
        return { success: false, message: "Advisor '#{advisor_name}' not found" } if advisor.nil?
        return { success: false, message: "Scribe cannot be removed from a conversation" } if advisor.scribe?

        participant = conversation.conversation_participants.find_by(advisor_id: advisor.id)
        return { success: false, message: "#{advisor.name} is not in this conversation" } if participant.nil?

        participant.destroy!

        create_info_message!(
          conversation: conversation,
          user: user,
          content: "#{actor_name(user)} removed #{advisor.name}"
        )

        { success: true, message: "#{advisor.name} has been removed from the conversation" }
      rescue StandardError => e
        { success: false, message: "Error removing advisor: #{e.message}" }
      end
    end
  end
end
