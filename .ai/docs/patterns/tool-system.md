# Tool System

RubyLLM-powered tool framework for AI agents (Scribe and Advisors).

## Overview

The tool system allows AI agents to perform actions within the application — querying data, creating records, and communicating with other agents. Tools inherit from `AI::Tools::BaseTool` and are adapted for RubyLLM via `AI::Adapters::RubyLLMToolAdapter`.

## Architecture

```
app/libs/ai/
├── tools/
│   ├── base_tool.rb                    # Base class for all tools
│   ├── conversations/
│   │   └── ask_advisor_tool.rb
│   ├── external/
│   │   └── browse_web_tool.rb
│   └── internal/
│       ├── create_memory_tool.rb
│       ├── get_conversation_summary_tool.rb
│       ├── list_conversations_tool.rb
│       ├── list_memories_tool.rb
│       ├── query_conversations_tool.rb
│       ├── query_memories_tool.rb
│       ├── read_conversation_tool.rb
│       ├── read_memory_tool.rb
│       └── update_memory_tool.rb
└── adapters/
    └── ruby_llm_tool_adapter.rb        # Wraps BaseTool for RubyLLM
```

## Tool Types

### Conversation tools
| Tool | Purpose | Write Access |
|------|---------|--------------|
| `ask_advisor` | Ask another advisor (posts in same conversation) | Yes |

### External tools
| Tool | Purpose | Write Access |
|------|---------|--------------|
| `browse_web` | Web search capabilities | Read-only |

### Internal tools
| Tool | Purpose |
|------|---------|
| `list_conversations` | List conversations in space |
| `query_conversations` | Find past conversations |
| `read_conversation` | Read conversation messages |
| `get_conversation_summary` | Get a summary of a specific conversation |
| `list_memories` | List memories in space |
| `query_memories` | Search memories by keyword |
| `read_memory` | Read a specific memory |
| `update_memory` | Edit a memory entry |
| `create_memory` | Create new memory entries |

## Base Class

```ruby
class AI::Tools::BaseTool
  def tool_name         # Override: return tool name string
  def tool_description  # Override: return description string
  def tool_parameters   # Override: return parameter hash
  def execute(params, context)  # Override: perform action
end
```

## RubyLLM Adapter

`AI::Adapters::RubyLLMToolAdapter` wraps a `BaseTool` instance for use with RubyLLM:

```ruby
adapter = AI::Adapters::RubyLLMToolAdapter.new(tool: my_tool, context: tool_context)
chat.with_tools(adapter)
```

## ask_advisor Tool

Special tool for inter-advisor communication:
- Creates a mention message in the current conversation
- Creates a pending placeholder for the target advisor
- Enqueues `GenerateAdvisorResponseJob` for async response
- Prevents self-asking (advisors cannot ask themselves)
- Posts in the same conversation (does NOT create a new conversation)

## Tool Execution Context

Tools receive a context object with:
- `conversation` — current conversation
- `space` — the space the conversation belongs to
- `advisor` — the advisor invoking the tool
- `user` — current user (if applicable)

## Testing

Tool tests use mock context objects and Mocha:

```ruby
test "query_memories finds matching memories" do
  context = stub(space: @space, conversation: @conversation, advisor: @advisor, user: nil)
  tool = AI::Tools::Internal::QueryMemoriesTool.new
  result = tool.execute({ "query" => "API" }, context)
  assert result[:success]
end
```
