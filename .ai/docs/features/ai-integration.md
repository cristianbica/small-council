# AI Integration

Multi-provider LLM support for AI advisor responses.

## Overview

Advisors generate responses using real LLM APIs. The system supports multiple providers (OpenAI, OpenRouter) with per-account configuration through a unified wrapper architecture.

## Architecture

### AI Lib Structure

```
app/libs/ai/
├── client.rb             # Unified wrapper: instance chat + class methods for provider/model ops
├── content_generator.rb  # High-level intent-based generation (wraps AI::Client)
├── model_manager.rb      # Model lifecycle management (enable/disable/sync)
├── adapters/
│   └── ruby_llm_tool_adapter.rb  # Wraps AI::Tools::BaseTool for RubyLLM
├── context_builders/
│   ├── base_context_builder.rb
│   ├── conversation_context_builder.rb
│   └── scribe_context_builder.rb
├── concerns/             # Shared model concerns
└── tools/
    ├── base_tool.rb
  ├── conversations/    # ask_advisor exists but is not currently wired
    ├── external/         # browse_web
  └── internal/         # memory + conversation + advisor/council management tools

app/services/
├── command_parser.rb     # Parse /commands and @mentions from user messages
└── ...
```

### AI::Client

`AI::Client` is **instance-based**. Instantiate it with a model, tools, and system prompt, then call `.chat`.

```ruby
# Instance usage (typical for response generation)
client = AI::Client.new(
  model: advisor.effective_llm_model,
  tools: [AI::Tools::Internal::QueryMemoriesTool.new],
  system_prompt: advisor.system_prompt
)
response = client.chat(
  messages: conversation.messages_for_llm,
  context: { space: space, conversation: conversation, user: user }
)
# response is AI::Model::Response: content, tool_calls, usage (AI::Model::TokenUsage)

# Provider-level class methods (for connection testing / model listing)
AI::Client.test_connection(provider: provider)
AI::Client.list_models(provider: provider)
```

Usage (tokens + cost) is automatically tracked inside `#chat` via `UsageRecord.create!`.
Model interactions (full request/response payloads) are recorded via event handlers registered in `AI::Client#register_interaction_handler` when `context[:message]` and account context are present. See [Model Interactions](model-interactions.md).

`AI::Client#chat` also injects system guidance messages from context in this order:
1. Council context (when available)
2. Memory index context (when available)
3. Response policy guidance (hard rules: thread-first, tools-only-when-needed, stricter for in-thread replies, no-tools when the user references above/below/previous thread context or provides substantial inline summary/context, and no `[speaker: ...]` response prefixes)

`GenerateAdvisorResponseJob` also sanitizes model output before saving by removing leading `[speaker: ...]` prefixes if present.

### Provider#api / LlmModel#api DSL

```ruby
# Provider-level (delegates to AI::Client class methods)
provider.api.list_models     # => AI::Client.list_models(provider: provider)
provider.api.test_connection # => AI::Client.test_connection(provider: provider)

# For model-level operations use AI::ContentGenerator or AI::Client.new directly
```

## Providers

### Supported
- **OpenAI** — GPT-4o, GPT-4o-mini, o1, o3-mini, etc.
- **OpenRouter** — OpenRouter-routed models (configured via a single provider key)

### Configuration
Each account manages its own providers:
- Name (e.g., "OpenAI Production")
- Provider type (enum: `openai`, `openrouter`)
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
- Free flag (set true when both input/output prices are 0.0)

### Advisor → LlmModel
Advisors reference an `LlmModel` instead of hardcoded provider/model strings.

## Content Generation

`AI::ContentGenerator` (in `app/libs/ai/content_generator.rb`) handles high-level advisor interactions:

```ruby
generator = AI::ContentGenerator.new
result = generator.generate_advisor_response(
  advisor: advisor,
  conversation: conversation,
  parent_message: message,
  context: { account: conversation.account, message: message }
)
# Returns AI::Model::Response with content, usage, and tool call metadata
```

## Error Handling

`AI::Client::APIError` and `AI::Client::RateLimitError` are raised when API calls fail. Model-level guards are handled inside `AI::ContentGenerator` (raises `AI::ContentGenerator::NoModelError` when no model is available).

## Background Jobs

`app/jobs/generate_advisor_response_job.rb` processes AI responses asynchronously:

1. Fetch pending message
2. Set tenant context for multi-tenancy
3. Determine if scribe followup (`is_scribe_followup` param)
4. Call `AI::ContentGenerator`
5. Update message with response content
6. Broadcast via Turbo Streams

Usage records are created automatically by `AI::Client#track_usage`.

### Error Handling
- API errors: Message marked as error with explanation
- Empty responses: Treated as error
- All errors logged with advisor/conversation context

## Turbo Streams

Real-time UI updates without page refresh:

- `<%= turbo_stream_from "conversation_#{@conversation.id}" %>` in show view
- Jobs broadcast updated message partials
- Pending messages show pulse animation

## Usage Tracking

Every API call creates a UsageRecord:
- Input/output token counts
- Provider type and model identifier
- Calculated cost (using per-model pricing from metadata)
- Timestamp and associations (account, conversation, message)

## Current Tool Wiring

`AI::ContentGenerator#advisor_tools` currently wires:

- **Non-scribe advisors:** no tools
- **Scribe tools (20 total):** read-only tools `query_memories`, `list_memories`, `read_memory`, `browse_web`, `query_conversations`, `list_conversations`, `read_conversation`, `get_conversation_summary` plus write/admin tools `create_memory`, `update_memory`, `create_advisor`, `list_advisors`, `get_advisor`, `update_advisor`, `create_council`, `list_councils`, `get_council`, `update_council`, `assign_advisor_to_council`, `unassign_advisor_from_council`

`ask_advisor_tool.rb` exists in `app/libs/ai/tools/conversations/` but is not currently included in `advisor_tools`.

## Routes

```
/providers                    # index, new, create
/providers/:id/edit           # edit, update, destroy
/providers/:id/models         # model management
```

## Testing

### Mock Pattern

`AI::Client` is instance-based. Stub `.new` to return a mock:

```ruby
# Correct — instance-based mock
mock_response = AI::Model::Response.new(content: "Response", usage: AI::Model::TokenUsage.new(input: 10, output: 5))
mock_client = mock("AI::Client")
mock_client.stubs(:chat).returns(mock_response)
AI::Client.stubs(:new).returns(mock_client)

# For provider-level class methods only:
AI::Client.stubs(:test_connection).returns({ success: true, model: "gpt-4o-mini" })
AI::Client.stubs(:list_models).returns([{ id: "gpt-4", name: "GPT-4" }])
```

### Test Files
- `test/services/provider_connection_tester_test.rb`
- `test/ai/unit/client_test.rb`
- `test/ai/unit/model_manager_test.rb`
- `test/jobs/generate_advisor_response_job_test.rb`

## Security

- API keys encrypted at rest (Rails encrypted attributes)
- Credentials never logged
- Per-account isolation via acts_as_tenant
- Tenant context explicitly set in background jobs
