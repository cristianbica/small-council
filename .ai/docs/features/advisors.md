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
4. Optional: use "Generate with AI" on the advisor form to open the reusable form-filler modal. Submitting a role description asynchronously fills `name`, `short_description`, and `system_prompt` when the structured result arrives.
5. Save - advisor is available for councils

See [Form Fillers](form-fillers.md) for the shared modal/runtime flow.

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
/spaces/:space_id/advisors               # index, new, create
/spaces/:space_id/advisors/:id           # show, edit, update, destroy
/councils/:id/edit_advisors              # edit council membership
/councils/:id/update_advisors            # update council membership
/form_filler/new?profile=advisor_profile # Turbo-streamed modal for AI form fill
/form_filler                             # queue async AI form fill request
```

Scribe membership is mandatory in every council and cannot be removed in the council membership editor.

### Models
- `Advisor`: name, system_prompt, llm_model_id, account_id, user_id (creator)
- `Advisor.belongs_to :llm_model`
- `Advisor.has_many :council_advisors, dependent: :destroy`
- `Advisor.has_many :councils, through: :council_advisors`
- `Advisor.has_many :messages, as: :sender` (polymorphic)

### Controllers
- `AdvisorsController`: CRUD within space context (`/spaces/:space_id/advisors`)
- Name normalization + validation enforce canonical handles
- Automatic account scoping via acts_as_tenant
- AI-assisted draft generation is now handled by `FormFillersController`, not a dedicated advisor generation endpoint

### Access Control
- All account users can view all advisors
- Any authenticated account user with access to the space can create/update/delete advisors
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

1. `AI.generate_advisor_response(..., async: true)` enqueues `AIRunnerJob`
2. `AI::Runner` executes `RespondTask` with `ConversationContext`
3. `AI::Client::Chat` performs model completion
4. API call made with:
   - System prompt as system message
   - Conversation history as context
   - User message as prompt
5. `ConversationResponseHandler` persists advisor message status/content and continues runtime sequencing

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

Regular advisors currently have no tool access.

Scribe gets memory-tool access through the runtime agent configuration.

### Tool Implementation

Tools are implemented under `app/libs/ai/tools/memories/` and `app/libs/ai/tools/advisors/`.
All tools inherit from `AI::Tools::AbstractTool` and are attached by runtime tasks.
See [Tool System pattern](../patterns/tool-system.md) for implementation details.

## Implementation Notes

- Advisors are scoped to account (acts_as_tenant)
- `belongs_to :space, optional: true` — Scribe belongs to a space; regular advisors can too
- `short_description` field (encrypted at rest) used in list views and AI profile generation
- `effective_llm_model`: returns advisor's model or falls back to account default
- System prompts can be overridden per council via `council_advisors.custom_prompt_override` (JSONB)
- Deleting an advisor raises error if messages exist (`restrict_with_error`)
- LLM model validated to belong to same account
