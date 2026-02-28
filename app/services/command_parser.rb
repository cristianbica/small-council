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

  # Check if content is a command
  def self.command?(content)
    return false if content.blank?
    content.start_with?("/") && COMMANDS.keys.any? { |cmd| content[1..].split.first&.downcase == cmd }
  end

  # Get list of available commands
  def self.available_commands
    COMMANDS.keys
  end
end
