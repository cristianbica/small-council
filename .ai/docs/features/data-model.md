# Data Model

Small Council uses a multi-tenant schema designed for AI advisor conversations.

## Entity Relationship Overview

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  accounts   │────▶│    users    │     │  providers  │
└─────────────┘     └─────────────┘     └─────────────┘
        │                   │                   │
        │                   │                   ▼
        ▼                   │           ┌─────────────┐
┌─────────────┐             │           │  llm_models │
│   spaces    │             │           └─────────────┘
└─────────────┘             │                   │
        │                   │                   ▼
        │                   │           ┌─────────────┐
        ▼                   │           │   advisors  │
┌─────────────┐             │           └─────────────┘
│   councils  │             │                   │
└─────────────┘             │           ┌─────────────────┐
        │                   │           │ council_advisors│
        │                   │           └─────────────────┘
        ▼                   ▼                    │
┌─────────────┐     ┌─────────────────┐          │
│ conv.parti- │     │  conversations  │◀─────────┘
│  cipants    │     └─────────────────┘
└─────────────┘             │
                            ▼
                    ┌─────────────┐     ┌───────────────┐
                    │   messages  │────▶│ usage_records │
                    └─────────────┘     └───────────────┘

┌─────────────┐     ┌─────────────────┐
│   memories  │────▶│ memory_versions │
└─────────────┘     └─────────────────┘
```

## Tables

### accounts
Root tenant table for multi-tenancy.
- `name`, `slug` (unique) — Account identification
- `settings` (jsonb) — Flexible account-level configuration
- `trial_ends_at` — Subscription management
- `default_llm_model_id` — FK to llm_models (optional)

### users
Scoped to accounts.
- `email` (currently globally unique)
- `password_digest` — For authentication
- `role` — member or admin
- `preferences` (jsonb) — User-specific settings

### providers
LLM provider configuration per account.
- `name` — Display name (e.g., "OpenAI Production")
- `provider_type` — Enum: `openai`, `openrouter`
- `credentials` (jsonb, encrypted attributes accessor) — API key and optional org id
- `enabled`

### llm_models
Models available under a provider.
- `name`, `identifier` — Display and API name
- `enabled` — Lifecycle flag
- `free` — True when both input/output prices are 0.0
- `metadata` (jsonb) — Capabilities, pricing, context window (synced from ruby_llm)
- Belongs to `provider` and `account`

### advisors
AI personas configured per account.
- `name`, `system_prompt` — Identity and behavior
- `llm_model_id` — FK to llm_models (replaces old `model_provider`/`model_id` strings)
- `global` — Whether available to all accounts
- `is_scribe` — True for the Scribe (moderator) advisor
- `metadata` (jsonb) — Version, tags, description
- Belongs to `account`; `space` is optional in model

### spaces
Contextual containers (workspaces).
- `name`, `description`
- After-create callback auto-creates a Scribe advisor

### councils
Groups of advisors that collaborate on conversations.
- `name`, `description`, `visibility` (private/shared)
- Belongs to user (owner), space, and account
- `configuration` (jsonb) — Routing rules, max rounds, etc.

### council_advisors
Join table linking councils to advisors with ordering.
- `position` — Display/speaking order
- `custom_prompt_override` (jsonb) — Per-council prompt adjustments

### conversations
Chat sessions within a council.
- Belongs to account, council, and user
- `title`, `status` (active/resolved/archived)
- `conversation_type` — Enum: `council_meeting`, `adhoc`
- `roe_type` — Rules of Engagement: `open`, `consensus`, `brainstorming`
- `scribe_initiated_count` — Tracks consecutive scribe-initiated interactions
- `context` (jsonb) — Shared context across messages
- `last_message_at` — For sorting

### conversation_participants
Join table: advisors participating in a conversation.
- `role` — `advisor` or `scribe`
- Belongs to `conversation` and `advisor`

### messages
Individual messages in conversations with polymorphic sender.
- `sender` polymorphic — references User or Advisor
- `role` — user, advisor, or system
- `content` — Plain text
- `content_blocks` (jsonb array) — Structured content (thinking, code, etc.)
- `metadata` (jsonb) — Tokens, latency, model version
- `status` — pending, responding, complete, error, cancelled

### usage_records
Billing and observability for AI API calls.
- Belongs to account, optionally to message
- `provider`, `model` — Which service was used
- `input_tokens`, `output_tokens` — Usage metrics
- `cost_cents` — Calculated cost
- `recorded_at` — When the usage occurred

### memories
Persistent knowledge entries per space.
- `title`, `content`
- `memory_type` — knowledge, note, summary, etc.
- `source` polymorphic — references Conversation or other source
- `created_by` polymorphic — references User or Advisor
- Versioned via `memory_versions`

### memory_versions
Audit trail for memory edits.
- `version_number`, `content`, `change_reason`
- Belongs to `memory`

### model_interactions
LLM API request/response recording per message.
- `sequence` — 0-indexed order per message
- `request_payload` (JSONB) — model, provider, temperature, system_prompt, tools, messages
- `response_payload` (JSONB) — content, tool_calls, tokens, model_used
- `model_identifier` — Denormalized for quick display
- `input_tokens`, `output_tokens` — Token counts
- `duration_ms` — Wall-clock API latency
- Belongs to `message` and `account`

## Design Decisions

### Scoped Multi-tenancy
All tables (except accounts) have `account_id` foreign keys. `acts_as_tenant` enforces row-level tenant isolation.

### JSONB for Flexibility
JSONB columns for configurations that evolve with AI capabilities:
- `accounts.settings`, `advisors.metadata`, `councils.configuration`
- `messages.content_blocks`, `messages.metadata`
- `llm_models.metadata` — capabilities, pricing, context window

### Polymorphic Associations
- `messages.sender` — User or Advisor
- `memories.source` — Conversation or other
- `memories.created_by` — User or Advisor

### LlmModel-based Advisors
Advisors now reference `LlmModel` instead of storing `model_provider`/`model_id` strings directly. This enables per-account model availability and usage tracking per model.
