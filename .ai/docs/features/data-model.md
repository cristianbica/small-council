# Data Model

Small Council uses a multi-tenant schema designed for AI advisor conversations.

## Entity Relationship Overview

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  accounts   │────▶│    users    │     │   advisors  │
└─────────────┘     └─────────────┘     └─────────────┘
        │                   │                   │
        │                   │                   │
        ▼                   │                   ▼
┌─────────────┐              │          ┌─────────────────┐
│    councils │◀─────────────┘          │ council_advisors│
└─────────────┘                         └─────────────────┘
        │
        ▼
┌─────────────────┐     ┌─────────────┐     ┌───────────────┐
│  conversations  │────▶│   messages  │◀────│ usage_records │
└─────────────────┘     └─────────────┘     └───────────────┘
```

## Tables

### accounts
Root tenant table for multi-tenancy.
- `name`, `slug` (unique) - Account identification
- `settings` (jsonb) - Flexible account-level configuration
- `trial_ends_at` - Subscription management

### users
Scoped to accounts. Members or admins of an account.
- `email` (scoped unique per account)
- `password_digest` - For authentication
- `role` - member or admin
- `preferences` (jsonb) - User-specific settings

### advisors
AI personas configured per account. Can be global (shared) or account-specific.
- `name`, `system_prompt` - Identity and behavior
- `model_provider`, `model_id` - LLM configuration (openai, anthropic, gemini)
- `model_config` (jsonb) - Temperature, max_tokens, etc.
- `metadata` (jsonb) - Version, tags, description
- `global` - Whether available to all accounts

### councils
Groups of advisors that collaborate on conversations.
- `name`, `description`, `visibility` (private/shared)
- Belongs to user (owner) and account
- `configuration` (jsonb) - Routing rules, max rounds, etc.

### council_advisors
Join table linking councils to advisors with ordering.
- `position` - Display/speaking order
- `custom_prompt_override` (jsonb) - Per-council prompt adjustments

### conversations
Chat sessions within a council.
- Belongs to account, council, and user
- `title`, `status` (active/archived)
- `context` (jsonb) - Shared context across messages
- `last_message_at` - For sorting recent conversations

### messages
Individual messages in conversations with polymorphic sender.
- `sender` polymorphic - references User or Advisor
- `role` - user, advisor, or system
- `content` - Plain text
- `content_blocks` (jsonb array) - Structured content (thinking, code, etc.)
- `metadata` (jsonb) - Tokens, latency, model version
- `status` - pending, complete, error

### usage_records
Billing and observability for AI API calls.
- Belongs to account, optionally to message
- `provider`, `model` - Which service was used
- `input_tokens`, `output_tokens` - Usage metrics
- `cost_cents` - Calculated cost
- `recorded_at` - When the usage occurred

## Design Decisions

### Scoped Multi-tenancy
All tables (except accounts) have `account_id` foreign keys. Models include comments indicating `acts_as_tenant` will be enabled once the gem is installed. This allows row-level tenant isolation.

### JSONB for Flexibility
JSONB columns are used for configurations that evolve with AI capabilities:
- `accounts.settings` - Tenant settings
- `advisors.model_config` - LLM hyperparameters
- `advisors.metadata` - Version tracking, tags
- `councils.configuration` - Routing logic
- `messages.content_blocks` - Rich content types
- `messages.metadata` - Token counts, model info

All JSONB columns have GIN indexes for efficient querying.

### Polymorphic Messages
The `sender` association on messages is polymorphic, allowing both User and Advisor models to send messages. This supports the pattern where advisors respond to user prompts within the same conversation flow.

### Usage Tracking
Every AI API call is recorded in `usage_records` with token counts and cost. This enables:
- Per-account billing
- Usage analytics
- Cost optimization insights

## Indexing Strategy

| Table | Index | Purpose |
|-------|-------|---------|
| accounts | slug (unique) | Lookup by subdomain/slug |
| accounts | settings (gin) | Query by settings keys |
| users | [account_id, email] (unique) | Scoped user lookup |
| advisors | model_config (gin) | Find by model settings |
| advisors | metadata (gin) | Tag/version queries |
| councils | [account_id, name] | List councils per account |
| councils | configuration (gin) | Query by config values |
| council_advisors | [council_id, advisor_id] (unique) | Prevent duplicates |
| conversations | [account_id, last_message_at] | Recent conversations list |
| conversations | context (gin) | Query by context data |
| messages | [conversation_id, created_at] | Chronological message load |
| messages | metadata (gin) | Query by token counts, etc. |
| messages | [sender_type, sender_id] | Polymorphic lookup |
| usage_records | [account_id, recorded_at] | Time-series billing queries |
