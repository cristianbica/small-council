# Advisors

AI personas with configurable LLM models and system prompts.

## Overview

- **Advisor** = An AI persona that participates in council conversations
- Each advisor has a unique personality defined by system prompts
- Advisors are associated with specific LLM models for response generation
- Can be reused across multiple councils

## Usage

### Creating an Advisor
1. Navigate to a council
2. Click "Add Advisor" or go to advisor management
3. Enter:
   - Name (display name, e.g., "Helper Bot")
   - System prompt (defines personality/behavior)
   - Select LLM model (from account's configured models)
4. Save - advisor is available for councils

### System Prompts
System prompts define advisor behavior:

```
You are a helpful assistant focused on clarity and brevity.
Provide concise answers with actionable next steps.
```

Best practices:
- Define role and tone clearly
- Include any constraints or specialties
- Mention response format preferences

### LLM Model Assignment
- Each advisor references one `LlmModel`
- Model determines which AI provider and specific model is used
- Changing models requires selecting from available account models

## Technical

### Routes
```
/councils/:council_id/advisors/new       # new, create
/councils/:council_id/advisors/:id/edit  # edit, update
/councils/:council_id/advisors/:id         # destroy
```

### Models
- `Advisor`: name, system_prompt, llm_model_id, account_id, user_id (creator)
- `Advisor.belongs_to :llm_model`
- `Advisor.has_many :council_advisors, dependent: :destroy`
- `Advisor.has_many :councils, through: :council_advisors`
- `Advisor.has_many :messages, as: :sender` (polymorphic)

### Controllers
- `AdvisorsController`: CRUD within council context
- Creator authorization for edit/update/destroy
- Automatic account scoping via acts_as_tenant

### Access Control
- All account users can view all advisors
- Only creator can modify/delete their advisors
- All users can add existing advisors to councils

## Relationships

```
Account
├── Advisors (created by users)
│   └── LlmModel (which provider/model to use)
└── Councils
    └── Advisors (via council_advisors join)
```

## AI Response Generation

When an advisor is triggered to respond:

1. `GenerateAdvisorResponseJob` enqueues
2. Job sets tenant context and `Current.space`
3. `AI::ContentGenerator#generate_advisor_response` builds context and calls `AI::Client.new(model:, tools:, system_prompt:).chat(...)`
4. API call made with:
   - System prompt as system message
   - Conversation history as context
   - User message as prompt
5. Response saved as Message with advisor as sender; `UsageRecord` auto-created

## Message Polymorphism

Advisors can send messages via polymorphic sender:

```ruby
class Message < ApplicationRecord
  belongs_to :sender, polymorphic: true  # User or Advisor
end

# Usage
message.sender = advisor  # Advisor instance
message.sender_type  # "Advisor"
message.sender_id    # advisor.id
```

## Tool Access

Advisors have access to 4 tools for interacting with the system:

| Tool | Purpose | Access |
|------|---------|--------|
| `query_memories` | Search space memories by keyword | Read-only |
| `query_conversations` | Find past conversations by topic | Read-only |
| `read_conversation` | Read messages from a specific conversation | Read-only |
| `ask_advisor` | Send a question to another advisor in the council | Write (creates messages) |

### ask_advisor Tool

The `ask_advisor` tool is the **only** way for advisors to communicate with each other:

```ruby
# Example tool usage
{
  advisor_name: "Systems Architect",
  question: "What do you think about using Docker for deployment?"
}
```

**Key behaviors:**
- Creates a message mentioning the target advisor
- Creates a pending placeholder for the advisor's response
- Enqueues `GenerateAdvisorResponseJob` for async response
- Prevents advisors from asking themselves
- Posts responses in the **same conversation** (changed from creating new conversations)

### Tool Implementation

Tools are implemented in `app/libs/ai/tools/internal/` and `app/libs/ai/tools/conversations/`:
- `AI::Tools::Conversations::AskAdvisorTool` - Inter-advisor communication
- `AI::Tools::Internal::QueryMemoriesTool` - Memory search
- `AI::Tools::Internal::QueryConversationsTool` - Conversation search
- `AI::Tools::Internal::ReadConversationTool` - Read conversation messages

All tools inherit from `AI::Tools::BaseTool` and receive context at execution time (not construction time).
See [Tool System pattern](../patterns/tool-system.md) for implementation details.

## Implementation Notes

- Advisors are scoped to account (acts_as_tenant)
- `belongs_to :space, optional: true` — Scribe belongs to a space; regular advisors can too
- `short_description` field (encrypted at rest) used in list views and AI profile generation
- `effective_llm_model`: returns advisor's model or falls back to account default
- `llm_model_configured?` always returns true for Scribe (uses special handling)
- System prompts can be overridden per council via `council_advisors.custom_prompt_override` (JSONB)
- Deleting an advisor raises error if messages exist (`restrict_with_error`)
- LLM model validated to belong to same account
