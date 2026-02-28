# AI Integration

Multi-provider LLM support for AI advisor responses.

## Overview

Advisors generate responses using real LLM APIs. The system supports multiple providers (OpenAI, OpenRouter) with per-account configuration through a unified wrapper architecture.

## Architecture

### AI Lib Structure

```
app/libs/ai/
├── client.rb             # Unified wrapper: class methods for provider/model ops
├── content_generator.rb  # High-level advisor response generation (replaces AIClient)
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
    ├── conversations/    # finish_conversation, ask_advisor, summarize_conversation
    ├── external/         # browse_web
    └── internal/         # list_conversations, query_conversations, read_conversation,
                          # list_memories, query_memories, read_memory, update_memory,
                          # get_conversation_summary, create_memory

app/services/
├── command_parser.rb     # Parse /commands and @mentions from user messages
└── ...
```

### AI::Client

`AI::Client` provides class methods for provider/model operations. Do **not** instantiate it directly for connection testing or model listing.

```ruby
# Provider-level operations (class methods)
AI::Client.test_connection(provider: provider)
AI::Client.list_models(provider: provider)

# Model-level operations (still via class or instance depending on use)
llm_model.api.info
llm_model.api.supports?(:vision)
llm_model.api.chat(messages, system_prompt: "...")
```

### Provider#api / LlmModel#api DSL

```ruby
# Provider-level
provider.api.list_models
provider.api.test_connection

# Model-level
llm_model.api.info
llm_model.api.chat(messages, system_prompt: "...")
```

## Providers

### Supported
- **OpenAI** — GPT-4o, GPT-4o-mini, o1, o3-mini, etc.
- **OpenRouter** — Multi-provider access (OpenAI, Anthropic, Google, etc.)

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
generator = AI::ContentGenerator.new(advisor: advisor, conversation: conversation, message: message)
result = generator.generate_response
# Returns: { content: "...", input_tokens: N, output_tokens: M, total_tokens: P, tool_calls: [], tool_results: [] }
```

## Error Handling

`AI::APIError` is raised when API calls fail. There is no `LLM::Client::MissingModelError` — model-level guard is handled inside `AI::Client`.

## Background Jobs

`app/jobs/generate_advisor_response_job.rb` processes AI responses asynchronously:

1. Fetch pending message
2. Set tenant context for multi-tenancy
3. Determine if scribe followup (`is_scribe_followup` param)
4. Call `AI::ContentGenerator`
5. Update message with response content
6. Create usage record
7. Broadcast via Turbo Streams

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

## Routes

```
/providers                    # index, new, create
/providers/:id/edit           # edit, update, destroy
/providers/:id/models         # model management
```

## Testing

### Mock Pattern
Always stub `AI::Client` **class methods**, not instance methods:

```ruby
# Correct
AI::Client.stubs(:test_connection).returns({ success: true, model: "gpt-4o-mini" })
AI::Client.stubs(:list_models).returns([{ id: "gpt-4", name: "GPT-4" }])

# Wrong — AI::Client uses class methods, not new + instance methods
AI::Client.expects(:new).returns(mock_client)  # Do NOT do this
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
