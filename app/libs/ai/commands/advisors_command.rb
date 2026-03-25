# frozen_string_literal: true

module AI
  module Commands
    class AdvisorsCommand < BaseCommand
      def validate
        errors << "Usage: /advisors" if args.any?
      end

      def execute(conversation:, user:)
        return { success: false, message: "Conversation space is required" } if conversation.space_id.blank?

        advisors = conversation.account.advisors.where(space_id: conversation.space_id).order(:name)
        { success: true, message: "Advisor list opened", advisors: advisors }
      end
    end
  end
end
