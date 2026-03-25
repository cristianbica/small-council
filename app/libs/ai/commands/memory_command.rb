# frozen_string_literal: true

module AI
  module Commands
    class MemoryCommand < BaseCommand
      def validate
        if args.size != 1
          errors << "Usage: /memory ID"
          return
        end

        errors << "Memory ID must be a number" unless args.first.to_s.match?(/\A\d+\z/)
      end

      def execute(conversation:, user:)
        return { success: false, message: "Conversation space is required" } if conversation.space_id.blank?

        memory_id = args.first.to_i
        memory = conversation.space.memories.find_by(id: memory_id)
        return { success: false, message: "Memory '#{memory_id}' not found" } if memory.nil?

        { success: true, message: "Memory opened", memory: memory }
      end
    end
  end
end
