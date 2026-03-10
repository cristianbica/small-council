# Command Pattern

Status: legacy. `CommandParser` was removed from the conversation runtime path.

## Overview

Command classes under `app/services/commands/` remain as plain service objects, but slash-command parsing from message text is no longer part of runtime orchestration.

## Structure

```
app/services/commands/
├── base_command.rb
└── invite_command.rb
```

## Usage

### Direct Command Usage

```ruby
command = Commands::InviteCommand.new(["@advisor-name"])
result = command.execute(conversation: conversation, user: current_user)
```

### Creating a New Command

1. Create a new class in `app/services/commands/`
2. Inherit from `Commands::BaseCommand`
3. Implement `validate` and `execute` methods
4. Invoke from an explicit endpoint/service (no parser registration)

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
