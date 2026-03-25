# frozen_string_literal: true

module AI
  module Commands
    class MemoriesCommand < BaseCommand
      def validate
        errors << "Usage: /memories" if args.any?
      end

      def execute(conversation:, user:)
        return { success: false, message: "Conversation space is required" } if conversation.space_id.blank?

        memories = conversation.space.memories.order(id: :desc)
        { success: true, message: "Memories list opened", memories: memories }
      end
    end
  end
end
