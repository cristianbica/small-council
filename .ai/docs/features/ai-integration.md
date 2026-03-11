# AI Integration

Multi-provider LLM support for AI advisor responses.

## Overview

Advisors generate responses using real LLM APIs. The system supports multiple providers (OpenAI, OpenRouter) with per-account configuration through a unified wrapper architecture.

## Architecture

### AI Lib Structure

```
app/libs/ai/
├── runner.rb             # Executes task/context/handler/tracker graph (sync or async)
├── client.rb             # Provider/model operations + chat entrypoint
├── client/chat.rb        # Class-based chat session wrapper
├── model_manager.rb      # Model lifecycle management (enable/disable/sync)
├── contexts/             # ConversationContext, SpaceContext
├── tasks/                # RespondTask, TextTask
├── handlers/             # ConversationResponseHandler, TurboFormFillerHandler
├── runtimes/             # Open/Consensus/Brainstorming conversation sequencing
├── trackers/             # UsageTracker, ModelInteractionTracker
└── tools/
    ├── abstract_tool.rb
    ├── advisors/
    └── memories/
```

### AI::Client

`AI::Client` is **class-based** for runtime chat entry and provider/model operations.

```ruby
# Chat session usage
chat = AI::Client.chat(model: advisor.effective_llm_model)
chat.instructions(advisor.system_prompt)
chat.add_message(role: :user, content: "Hello")
result = AI::Result.new
chat.complete(result)

# Provider-level class methods (for connection testing / model listing)
AI::Client.test_connection(provider: provider)
AI::Client.list_models(provider: provider)
AI::Client.model_info(model: llm_model)
```
Runtime interaction records are captured through `AI::Trackers::ModelInteractionTracker` callback hooks and persisted to `ModelInteraction` (plus mirrored tool traces on `messages.tool_calls`). See [Model Interactions](model-interactions.md).

For runtime-owned response generation, sanitization and state persistence now live in `AI::Handlers::ConversationResponseHandler`.

## API Entry Points

Defined in `app/libs/ai.rb`:

- `AI.run(task:, context:, handler: nil, tracker: nil, async: false)`
    - Generic runner entrypoint.
    - Accepts symbolic/hash task and context definitions resolved by `AI::Runner`.
    - Used by adhoc conversation title generation in `app/models/conversation.rb` with:
        - task: `type: :text`, prompt `conversations/title_generator`, tool `conversations/update_conversation`
        - context: `type: :conversation`
        - `async: true`
- `AI.generate_advisor_response(advisor:, message:, prompt: nil, tracker: :model_interaction, async: true)`
    - Convenience wrapper for conversation advisor/scribe replies.
    - Builds a `respond` task with `ConversationContext`, `ConversationResponseHandler`, and `ModelInteractionTracker` by default.
    - Called by conversation runtimes (`app/libs/ai/runtimes/conversation_runtime.rb`) and retry flow (`app/controllers/messages_controller.rb`).
- `AI.generate_text(description:, prompt:, schema: nil, space:, handler: nil, async: false, **args)`
    - Convenience wrapper for utility text/structured generation.
    - Builds a `text` task with `SpaceContext`.
    - Called by form filler flow in `app/controllers/form_fillers_controller.rb`.

### Provider#api / LlmModel#api DSL

```ruby
# Provider-level (delegates to AI::Client class methods)
provider.api.list_models     # => AI::Client.list_models(provider: provider)
provider.api.test_connection # => AI::Client.test_connection(provider: provider)

# For model-level operations use AI::Client.model_info
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

Conversation replies run through `AI::Runner`:

- `MessagesController#create` calls `AI.runtime_for_conversation(@conversation).user_posted(@message)`
- Runtime classes create `pending` advisor placeholders and call `AI.generate_advisor_response`
- `AI.generate_advisor_response` builds a `RespondTask` + `ConversationContext`, then runs via `AI::Runner`
- Async runs enqueue `AIRunnerJob`
- `AI::Handlers::ConversationResponseHandler` updates message status/content and re-enters runtime sequencing with `advisor_responded`

The utility-generation path for structured form filling uses the same runner primitives:

- `FormFillersController#create` calls `AI.generate_text(..., async: true)`
- `AI.generate_text` builds a `TextTask` + `SpaceContext`
- `AI::Runner` executes with default `UsageTracker`
- `AI::Handlers::TurboFormFillerHandler` broadcasts the result back to the form

See [Form Fillers](form-fillers.md) for the UI and request flow.

Adhoc auto-title generation is model-driven:

- `Conversation` callback calls `AI.run(..., async: true)`
- Prompt: `conversations/title_generator`
- Tool: `conversations/update_conversation`
- Title state transitions are persisted as `system_generated -> agent_generating -> agent_generated`

See patterns: [Agents](../patterns/agents.md), [Prompts](../patterns/prompts.md), [Tasks](../patterns/tasks.md), [Tool System](../patterns/tool-system.md)

## Error Handling

`AI::Client::APIError` and `AI::Client::RateLimitError` are raised when API calls fail.

## Background Jobs

`app/jobs/ai_runner_job.rb` is the canonical async entrypoint for runtime tasks:

1. Receives serialized `task`, `context`, `handler`, and optional `tracker`
2. Rehydrates and executes through `AI::Runner`

Retry and standard advisor response flows both enqueue `AIRunnerJob` through `AI.generate_advisor_response(..., async: true)`.

Usage records are created automatically by `AI::Trackers::UsageTracker`.

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

For runner-managed flows, `AI::Trackers::UsageTracker` writes usage records after task completion.

## Current Tool Wiring

Tool wiring is task/agent-driven:

- `AI::Tasks::BaseTask#register_tools` resolves tool refs from `agent.tools`
- `AI.tools(*refs)` resolves classes through `AI::Tools::AbstractTool::REGISTRY`
- `AI::Agents::AdvisorAgent` currently returns `memories/*` for scribe contexts and no tools for non-scribe contexts

## Routes

```
/providers                    # index, new, create
/providers/:id/edit           # edit, update, destroy
/providers/:id/models         # model management
```

## Testing

### Mock Pattern

`AI::Client` is class-based for chat creation and provider/model operations:

```ruby
# Class-based chat entry
chat = mock("chat")
AI::Client.stubs(:chat).returns(chat)

# Provider/model class methods:
AI::Client.stubs(:test_connection).returns({ success: true, model: "gpt-4o-mini" })
AI::Client.stubs(:list_models).returns([{ id: "gpt-4", name: "GPT-4" }])
```

### Test Files
- `test/services/provider_connection_tester_test.rb`
- `test/ai/unit/client_test.rb`
- `test/ai/unit/model_manager_test.rb`
- `test/ai/runner_test.rb`
- `test/libs/ai/tasks/respond_task_test.rb`

## Security

- API keys encrypted at rest (Rails encrypted attributes)
- Credentials never logged
- Per-account isolation via acts_as_tenant
- Tenant context explicitly set in background jobs
