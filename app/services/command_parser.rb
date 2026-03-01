# app/services/command_parser.rb
class CommandParser
  COMMANDS = {
    "invite" => Commands::InviteCommand
  }.freeze

  # Parse a command from message content
  # Returns command instance if valid command, nil otherwise
  def self.parse(content)
    return nil if content.blank?
    return nil unless content.start_with?("/")

    parts = content[1..].split
    command_name = parts.first&.downcase
    args = parts[1..] || []

    command_class = COMMANDS[command_name]
    return nil unless command_class

    command_class.new(args)
  end
end
