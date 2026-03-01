# Model Interactions

Records every LLM API request/response for AI-generated messages and exposes them through a per-message modal in the conversation UI.

## Overview

When an advisor generates a response, each `AI::Client#chat` call creates a `ModelInteraction` record capturing the full request/response round-trip. Users can inspect these via a terminal/code icon next to advisor messages.

## Table Schema

```
model_interactions
├── account_id      (FK, tenant)
├── message_id      (FK)
├── sequence        (integer, 0-indexed per message)
├── request_payload (JSONB — model, provider, temperature, system_prompt, tools, messages)
├── response_payload(JSONB — content, tool_calls, tokens, model_used)
├── model_identifier(string, denormalized)
├── input_tokens    (integer)
├── output_tokens   (integer)
├── duration_ms     (float)
└── timestamps
```

## Model

`ModelInteraction` — `app/models/model_interaction.rb`

- `belongs_to :message`, `belongs_to :account`
- `acts_as_tenant :account`
- `scope :chronological` — orders by sequence ASC
- `total_tokens` — sums input + output tokens
- Message has `has_many :model_interactions, dependent: :destroy`

## Recording Hook

`AI::Client#record_interaction` is called after `track_usage` inside `#chat`:

```ruby
# In AI::Client#chat (non-streaming path)
response = ruby_llm_chat.complete
track_usage(response, context)
record_interaction(messages, response, context, duration_ms)  # ← here
normalize_response(response)
```

Key behaviors:
- Only records when `context[:message]` is present (advisor responses only)
- Rescue-and-log pattern — recording failures never break AI responses
- Truncates message content (500 chars) and response content (1000 chars) in payloads
- Sequence auto-determined from existing interaction count per message

## UI

- **Icon**: Terminal/code icon next to AI-generated messages (both `_message_thread.html.erb` and `_message.html.erb`)
- **Modal**: DaisyUI `<dialog>` with collapse accordion showing request/response JSON per interaction
- First interaction expanded by default; header shows model, token count, and duration

## Design Decisions

| Decision | Rationale |
|---|---|
| JSONB for request/response | Schemas vary by provider and evolve; GIN indexed for queryability |
| Truncated content in payloads | Full conversation history could be huge; keeps storage manageable |
| No encryption on payloads | Content already encrypted at message level; JSONB encryption prevents GIN indexing |
| Rescue-and-log | Same pattern as `track_usage`; recording must never break AI responses |
| No new routes/controller | Interactions eager-loaded with messages; rendered inline via modal |
| No Stimulus controller | Uses existing `<dialog>.showModal()` pattern |

## Testing

```bash
bin/rails test test/models/model_interaction_test.rb    # 15 model tests
bin/rails test test/ai/unit/client_test.rb              # includes 4 recording tests
```
