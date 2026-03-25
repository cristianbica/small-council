# frozen_string_literal: true

module AI
  module Commands
    class InviteCommand < BaseCommand
      def validate
        if args.empty?
          errors << "Usage: /invite advisor-name"
          return
        end

        errors << "Please provide an advisor name like advisor-name" if normalized_advisor_name(args.first).blank?
      end

      def execute(conversation:, user:)
        advisor_name = normalized_advisor_name(args.first)

        return { success: false, message: "Conversation space is required" } if conversation.space_id.blank?

        advisor = conversation.account.advisors.find_by(space_id: conversation.space_id, name: advisor_name)
        return { success: false, message: "Advisor '#{advisor_name}' not found" } if advisor.nil?
        return { success: false, message: "Scribe is automatically present" } if advisor.scribe?
        return { success: false, message: "#{advisor.name} is already in this conversation" } if conversation.advisors.include?(advisor)

        conversation.conversation_participants.create!(
          advisor: advisor,
          role: "advisor",
          position: conversation.conversation_participants.maximum(:position).to_i + 1
        )

        create_info_message!(
          conversation: conversation,
          user: user,
          content: "#{actor_name(user)} added #{advisor.name}"
        )

        { success: true, message: "#{advisor.name} has been invited to the conversation" }
      rescue StandardError => e
        { success: false, message: "Error inviting advisor: #{e.message}" }
      end
    end
  end
end
