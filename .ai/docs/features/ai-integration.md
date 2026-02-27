# AI Integration

Multi-provider LLM support for AI advisor responses.

## Overview

Advisors generate responses using real LLM APIs. The system supports multiple providers (OpenAI, OpenRouter) with per-account configuration through a unified wrapper architecture.

## Architecture

### LLM Module Structure

```
app/services/llm/
├── llm.rb              # Module definition, APIError class
├── client.rb           # Unified wrapper for all provider operations
└── model_manager.rb    # Model lifecycle management
```

### LLM::Client

The `LLM::Client` class provides a unified interface for all LLM operations:

```ruby
# Provider-level operations
client = LLM::Client.new(provider: provider)
client.list_models      # List available models
client.test_connection  # Validate credentials

# Model-level operations
client = LLM::Client.new(provider: provider, model: llm_model)
client.info             # Get model metadata
client.supports?(:vision)  # Check capabilities
client.chat(messages, system_prompt: "...")  # Chat completion
```

## Providers

### Supported
- **OpenAI** - GPT-4o, GPT-4o-mini, o1, o3-mini, etc.
- **OpenRouter** - Multi-provider access (OpenAI, Anthropic, Google, etc.)

### Configuration
Each account manages its own providers:
- Name (e.g., "OpenAI Production")
- Provider type (enum: openai, openrouter)
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
- Name (display name, e.g., "GPT-4o")
- Identifier (API identifier, e.g., "gpt-4o")
- Enabled flag for lifecycle management
- Metadata (capabilities, pricing, context window) synced from ruby_llm

### Advisor → LlmModel
Advisors reference an LlmModel instead of hardcoded provider/model strings. This enables:
- Easy model switching per advisor
- Per-account model availability
- Usage tracking per model

## DSL: provider.api and model.api

Models provide convenient API accessors:

```ruby
# Provider-level operations
provider.api.list_models
provider.api.test_connection

# Model-level operations
llm_model.api.info
llm_model.api.supports?(:vision)
llm_model.api.chat(messages, system_prompt: "...")
```

These methods return `LLM::Client` instances:
- `Provider#api` - Client without model (provider operations only)
- `LlmModel#api` - Client with model (all operations including chat)

## Error Handling

### LLM::APIError
Raised when API calls fail:

```ruby
begin
  result = client.chat(messages)
rescue LLM::APIError => e
  # Handle API failure
end
```

### LLM::Client::MissingModelError
Raised when model-level operations are called on a client without a model:

```ruby
client = LLM::Client.new(provider: provider)
client.chat(messages)  # Raises MissingModelError
```

## AI Client Service

`app/services/ai_client.rb` handles high-level advisor interactions:

```ruby
client = AIClient.new(advisor: advisor, conversation: conversation, message: message)
result = client.generate_response
# Returns: { content: "...", input_tokens: N, output_tokens: M, total_tokens: P, tool_calls: [], tool_results: [] }
```

### How AIClient Uses the Wrapper

AIClient uses RubyLLM for chat with tool support:

```ruby
# Configure RubyLLM context
context = RubyLLM.context do |config|
  config.openai_api_key = model.provider.api_key
end

# Create chat with tools
chat = context.chat(model: model.identifier).with_tools(
  RubyLLMTools::AdvisorQueryMemoriesTool,
  RubyLLMTools::AdvisorAskAdvisorTool
)

# Add system instructions and messages
chat.with_instructions(system_prompt)
messages.each { |msg| chat.add_message(role: msg[:role], content: msg[:content]) }

# Execute and handle tool calls
response = chat.complete
results = handle_tool_calls(response, chat)
```

### Features
- Unified provider interface via LLM::Client
- **Tool system integration** - Advisors can use 4 tools (query_memories, query_conversations, read_conversation, ask_advisor)
- Automatic retry with exponential backoff
- Conversation context building (system prompt + history + memory context)
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
- Calculated cost (using per-model pricing from metadata)
- Timestamp and associations (account, conversation, message)

## Routes

```
/providers                    # index, new, create
/providers/:id/edit           # edit, update, destroy
/providers/:id/models         # model management
```

## Testing

### Model Tests
- Provider: validation, encryption, scopes
- LlmModel: validation, metadata sync, scopes
- Advisor: llm_model association, provider delegation

### Service Tests
- LLM::Client: provider operations, chat, error handling
- LLM::ModelManager: enable/disable, model discovery
- AIClient: message building, response parsing, error handling
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
- No rate limiting per account
- No provider health checks or failover
