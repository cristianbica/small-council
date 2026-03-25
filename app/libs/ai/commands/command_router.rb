# frozen_string_literal: true

module AI
  module Commands
    class CommandRouter
      def self.execute(content:, conversation:, user:)
        parsed = parse(content)
        return nil if parsed.nil?

        command_type = parsed[:command]
        command_class = AI.command(command_type)
        command = command_class.new(parsed[:args])

        unless command.valid?
          return {
            success: false,
            action: command_type,
            message: command.errors.join(", ")
          }
        end

        command.execute(conversation: conversation, user: user).merge(action: command_type)
      rescue AI::ResolutionError
        {
          success: false,
          action: parsed&.dig(:command) || "unknown",
          message: "Unknown command. Available commands: /advisors, /invite, /kick, /memories, /memory, /attach"
        }
      end

      def self.parse(content)
        return nil if content.blank?

        raw = content.to_s.strip
        return nil unless raw.start_with?("/")

        tokens = raw.delete_prefix("/").split(/\s+/)
        return nil if tokens.empty?

        {
          command: tokens.shift.downcase,
          args: tokens
        }
      end
    end
  end
end
