# Tool System

RubyLLM-powered tool framework for AI agents (Scribe and Advisors).

## Overview

The tool system allows AI agents to perform actions within the application - querying data, creating records, and communicating with other agents. Tools are implemented using the RubyLLM library with custom wrappers.

## Architecture

```
app/services/
├── scribe_tool.rb                 # Base class for Scribe tools (full access)
├── advisor_tool.rb                # Base class for Advisor tools (read-only default)
├── scribe_tool_executor.rb        # Tool execution and registry
├── tool_execution_context.rb      # Context object for tool execution
├── scribe_tools/                  # Scribe-specific tools
│   ├── finish_conversation_tool.rb
│   ├── create_memory_tool.rb
│   ├── query_memories_tool.rb
│   └── browse_web_tool.rb
├── advisor_tools/                 # Advisor-specific tools
│   ├── query_memories_tool.rb
│   ├── query_conversations_tool.rb
│   ├── read_conversation_tool.rb
│   └── ask_advisor_tool.rb
└── ruby_llm_tools/                # RubyLLM wrapper classes
    ├── create_memory_tool.rb
    ├── query_memories_tool.rb
    ├── ask_advisor_tool.rb
    └── ... (wrappers for all tools)
```

## Tool Types

### Scribe Tools (4 tools)

| Tool | Purpose | Write Access |
|------|---------|--------------|
| `finish_conversation` | Conclude and summarize conversation | Yes |
| `create_memory` | Create new memory entries | Yes |
| `query_memories` | Search memories by keyword | Read-only |
| `browse_web` | Web search capabilities | Read-only |

### Advisor Tools (4 tools)

| Tool | Purpose | Write Access |
|------|---------|--------------|
| `query_memories` | Search space memories | Read-only |
| `query_conversations` | Find past conversations | Read-only |
| `read_conversation` | Read conversation messages | Read-only |
| `ask_advisor` | Communicate with other advisors | Yes |

## Base Classes

### ScribeTool

Full-access base class for Scribe tools:

```ruby
class ScribeTool
  def tool_name        # Override: return tool name string
  def tool_description # Override: return description string
  def tool_parameters  # Override: return parameter hash
  def execute(params, context)  # Override: perform action
  def validate_params(params)   # Built-in parameter validation
end
```

### AdvisorTool

Read-only by default base class for Advisor tools:

```ruby
class AdvisorTool
  def read_only?       # Override to return false for write access
  # ... same interface as ScribeTool
end
```

## Tool Execution

### Registration

Tools are registered in `ScribeToolExecutor`:

```ruby
SCRIBE_TOOLS = [
  ScribeTools::FinishConversationTool,
  ScribeTools::CreateMemoryTool,
  # ...
].freeze

ADVISOR_TOOLS = [
  AdvisorTools::QueryMemoriesTool,
  AdvisorTools::AskAdvisorTool,
  # ...
].freeze
```

### Execution Flow

1. **AI Response Generation**: `AIClient` sets up RubyLLM chat with tools
2. **Tool Call**: AI decides to use a tool, RubyLLM parses the request
3. **Context Setup**: `ToolExecutionContext` created with conversation, space, advisor, user
4. **Execution**: `ScribeToolExecutor.execute` finds tool, validates params, executes
5. **Result**: Tool result formatted and returned to AI for follow-up

### Context Object

```ruby
context = ToolExecutionContext.new(
  conversation: conversation,
  space: space,
  advisor: advisor,
  user: user
)
```

## RubyLLM Integration

Tools are wrapped for RubyLLM compatibility:

```ruby
class RubyLLMTools::CreateMemoryTool < RubyLLM::Tool
  def create_memory(title:, content:, memory_type: "knowledge")
    # Tool logic here
  end
end
```

Tools are attached to chat sessions:

```ruby
chat = context.chat(model: model.identifier).with_tools(
  RubyLLMTools::AdvisorQueryMemoriesTool,
  RubyLLMTools::AdvisorAskAdvisorTool
)
```

## ask_advisor Tool

Special tool for inter-advisor communication:

- Creates a mention message in the current conversation
- Creates a pending placeholder for the target advisor
- Enqueues `GenerateAdvisorResponseJob` for async response
- Prevents self-asking (advisors cannot ask themselves)
- **Changed**: Previously created new conversations, now posts in same conversation

## Usage Guidelines

- Keep tools focused on single responsibility
- Use read-only where possible ( AdvisorTool default)
- Override `read_only?` only when necessary
- Validate all parameters before execution
- Return consistent result format: `{ success: boolean, message: string, data: hash }`
- Log tool executions for debugging

## Testing

Tool tests use mock context objects:

```ruby
test "query_memories finds matching memories" do
  context = mock_tool_context(space: @space)
  tool = AdvisorTools::QueryMemoriesTool.new
  result = tool.execute({ "query" => "API" }, context)

  assert result[:success]
  assert_includes result[:message], "Found"
end
```
