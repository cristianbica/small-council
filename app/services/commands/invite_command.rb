# app/services/commands/invite_command.rb
module Commands
  class InviteCommand < BaseCommand
    ADVISOR_HANDLE_FORMAT = /\A@[a-z0-9]+(?:-[a-z0-9]+)*\z/i

    def validate
      if args.empty?
        @errors << "Usage: /invite @advisor-name"
        return
      end

      mention = args.first
      unless mention.match?(ADVISOR_HANDLE_FORMAT)
        @errors << "Please mention an advisor with @advisor-name"
      end
    end

    def execute(conversation:, user:)
      advisor_name = args.first.delete_prefix("@").downcase

      return { success: false, message: "Conversation space is required" } if conversation.space_id.blank?

      advisor = conversation.account.advisors.find_by(space_id: conversation.space_id, name: advisor_name)

      if advisor.nil?
        return { success: false, message: "Advisor '@#{advisor_name}' not found" }
      end

      # Cannot invite scribe (scribe is auto-present) - check this first for clearer error
      if advisor.scribe?
        return { success: false, message: "Scribe is automatically present" }
      end

      # Check if advisor is already in conversation
      if conversation.advisors.include?(advisor)
        return { success: false, message: "#{advisor.name} is already in this conversation" }
      end

      # Add advisor to conversation
      conversation.conversation_participants.create!(
        advisor: advisor,
        role: "advisor",
        position: conversation.conversation_participants.maximum(:position).to_i + 1
      )

      { success: true, message: "#{advisor.name} has been invited to the conversation" }
    rescue => e
      { success: false, message: "Error inviting advisor: #{e.message}" }
    end
  end
end
