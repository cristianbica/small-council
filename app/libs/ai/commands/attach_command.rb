# frozen_string_literal: true

module AI
  module Commands
    class AttachCommand < BaseCommand
      def validate
        if args.size != 1
          errors << "Usage: /attach ID"
          return
        end

        errors << "Memory ID must be a number" unless args.first.to_s.match?(/\A\d+\z/)
      end

      def execute(conversation:, user:)
        return { success: false, message: "Conversation space is required" } if conversation.space_id.blank?

        memory_id = args.first.to_i
        memory = conversation.space.memories.find_by(id: memory_id)
        return { success: false, message: "Memory '#{memory_id}' not found" } if memory.nil?

        conversation.messages.create!(
          account: conversation.account,
          sender: user,
          role: "user",
          message_type: "memory_attachment",
          status: "complete",
          content: attachment_content(memory),
          metadata: {
            memory_id: memory.id,
            memory_title: memory.title
          }
        )

        { success: true, message: "Memory attached" }
      rescue StandardError => e
        { success: false, message: "Error attaching memory: #{e.message}" }
      end

      private

      def attachment_content(memory)
        "Attached memory ##{memory.id}: #{memory.title}\n\n#{memory.content}"
      end
    end
  end
end
