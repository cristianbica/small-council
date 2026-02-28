# Command Pattern

## Overview

The command pattern provides a structured way to handle user input that starts with `/`. Each command is a self-contained class that handles parsing, validation, and execution.

## Structure

```
app/services/
├── command_parser.rb          # Entry point - parses commands
└── commands/
    ├── base_command.rb        # Abstract base class
    └── invite_command.rb      # Concrete command implementation
```

## Usage

### Parsing Commands

```ruby
# In a controller or service
command = CommandParser.parse("/invite @advisor_name")

if command
  if command.valid?
    result = command.execute(conversation: conversation, user: current_user)
    # result is a hash: { success: true/false, message: "..." }
  else
    # Handle validation errors
    command.errors.each { |error| puts error }
  end
end
```

### Creating a New Command

1. Create a new class in `app/services/commands/`
2. Inherit from `Commands::BaseCommand`
3. Implement `validate` and `execute` methods
4. Register in `CommandParser::COMMANDS`

```ruby
# app/services/commands/my_command.rb
module Commands
  class MyCommand < BaseCommand
    def validate
      if args.empty?
        @errors << "Usage: /mycommand <argument>"
      end
    end

    def execute(conversation:, user:)
      # Implementation here
      { success: true, message: "Command executed" }
    rescue => e
      { success: false, message: "Error: #{e.message}" }
    end
  end
end

# app/services/command_parser.rb
COMMANDS = {
  "invite" => Commands::InviteCommand,
  "mycommand" => Commands::MyCommand  # Add here
}.freeze
```

## Design Principles

1. **Single Responsibility**: Each command does one thing
2. **Explicit Validation**: Commands validate their own arguments
3. **Uniform Interface**: All commands return `{ success:, message: }`
4. **Extensibility**: New commands don't require changes to parsing logic

## Testing

Commands are easy to test in isolation:

```ruby
class Commands::MyCommandTest < ActiveSupport::TestCase
  test "valid with correct arguments" do
    cmd = Commands::MyCommand.new([ "arg1" ])
    assert cmd.valid?
  end

  test "execute returns success result" do
    cmd = Commands::MyCommand.new([ "arg1" ])
    result = cmd.execute(conversation: conversation, user: user)
    assert result[:success]
  end
end
```
