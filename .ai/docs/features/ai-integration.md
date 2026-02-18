# AI Integration

Multi-provider LLM support for AI advisor responses.

## Overview

Advisors generate responses using real LLM APIs. The system supports multiple providers (OpenAI, Anthropic, GitHub Models) with per-account configuration.

## Providers

### Supported
- **OpenAI** - GPT-4, GPT-3.5 via official API
- **Anthropic** - Claude 3 models via official API
- **GitHub Models** - OpenAI-compatible API hosted on Azure

### Configuration
Each account manages its own providers:
- Name (e.g., "OpenAI Production")
- Provider type (enum)
- API key (encrypted at rest)
- Organization ID (OpenAI only, optional)
- Enabled flag

### Encrypted Credentials
API keys are encrypted using Rails encrypted attributes. Requires:
- `RAILS_MASTER_KEY` environment variable in production
- `config/credentials.yml.enc` with `active_record_encryption` keys

## Models

### LlmModel
Each provider can have multiple models:
- Name (display name, e.g., "GPT-4")
- Identifier (API identifier, e.g., "gpt-4")
- Enabled/Deprecated/Deleted flags for lifecycle management
- Soft delete pattern (deleted_at timestamp)

### Advisor → LlmModel
Advisors reference an LlmModel instead of hardcoded provider/model strings. This enables:
- Easy model switching per advisor
- Per-account model availability
- Usage tracking per model

## AI Client Service

`app/services/ai_client.rb` handles API calls:

```ruby
client = AiClient.new(advisor: advisor, conversation: conversation, message: message)
result = client.generate_response
# Returns: { content: "...", input_tokens: N, output_tokens: M, total_tokens: P }
```

### Features
- Provider-specific message formatting (OpenAI vs Anthropic)
- Automatic retry with exponential backoff
- Conversation context building (system prompt + history)
- Error handling with custom exception classes

## Background Jobs

`app/jobs/generate_advisor_response_job.rb` processes AI responses asynchronously:

1. Fetch pending message
2. Set tenant context for multi-tenancy
3. Call AI Client
4. Update message with response content
5. Create usage record
6. Broadcast via Turbo Streams

### Error Handling
- API errors: Message marked as error with explanation
- Empty responses: Treated as error
- All errors logged with advisor/conversation context

## Turbo Streams

Real-time UI updates without page refresh:

- `<%= turbo_stream_from "conversation_#{@conversation.id}" %>` in show view
- Jobs broadcast `turbo_stream_replace_to` with updated message partial
- Pending messages show pulse animation
- Error messages show distinct styling

## Usage Tracking

Every API call creates a UsageRecord:

- Input/output token counts
- Provider type and model identifier
- Calculated cost (placeholder rates; per-model pricing in Phase 2)
- Timestamp and associations (account, conversation, message)

## Routes

```
/providers              # index, new, create
/providers/:id/edit      # edit, update, destroy
```

## Testing

### Model Tests
- Provider: validation, encryption, scopes
- LlmModel: validation, soft delete, scopes
- Advisor: llm_model association, provider delegation

### Service Tests
- AiClient: message building, response parsing, error handling
- Uses Mocha for mocking API calls

### Job Tests
- GenerateAdvisorResponseJob: success path, error handling, idempotency

### Integration Tests
- Full flow: message post → job enqueue → response generation

## Security

- API keys encrypted at rest (Rails encrypted attributes)
- Credentials never logged
- Per-account isolation via acts_as_tenant
- Tenant context explicitly set in background jobs

## Limitations (Phase 1)

- No streaming responses (full response only)
- Placeholder cost calculation (needs per-model pricing table)
- No rate limiting per account
- No provider health checks or failover
- Console/seeds required for model creation (no UI yet)
