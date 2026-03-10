# Model Interactions

Records every LLM API request/response for AI-generated messages and exposes them through a per-message modal in the conversation UI.

## Overview

During advisor response generation, `AI::Trackers::ModelInteractionTracker` subscribes to RubyLLM callbacks (`on_end_message`, `on_tool_call`, `on_tool_result`) and persists interaction rows to `ModelInteraction`.

The same tracker also mirrors tool activity to `messages.tool_calls` so each advisor message retains a compact ordered tool trace.

## Table Schema

```
model_interactions
├── account_id       (FK, tenant)
├── message_id       (FK)
├── sequence         (integer, 0-indexed per message)
├── interaction_type (string, "chat" or "tool", default "chat")
├── request_payload  (JSONB — model, provider, temperature, system_prompt, messages)
├── response_payload (JSONB — messages, input_tokens, output_tokens, model)
├── model_identifier (string, denormalized)
├── input_tokens     (integer)
├── output_tokens    (integer)
├── duration_ms      (float)
└── timestamps
```

## Model

`ModelInteraction` — `app/models/model_interaction.rb`

- `belongs_to :message`, `belongs_to :account`
- `acts_as_tenant :account`
- `validates :interaction_type, presence: true, inclusion: { in: %w[chat tool] }`
- `scope :chronological` — orders by sequence ASC
- `total_tokens` — sums input + output tokens
- Message has `has_many :model_interactions, dependent: :destroy`

## Recording Flow

`AI::Trackers::ModelInteractionTracker` (`app/libs/ai/trackers/model_interaction_tracker.rb`) behavior:

- `register(chat)` attaches callback handlers
- `on_end_message` records `interaction_type = "chat"`
- `on_tool_call` + `on_tool_result` pair into `interaction_type = "tool"`
- `track(result)` persists buffered tool trace entries to `messages.tool_calls`

Key behaviors:
- Records only when context has both `message` and `account`
- Uses rescue-and-log so tracker failures do not break generation
- Computes duration separately for chat and tool rounds
- Stores full payloads for debugging and auditability

## UI

- Interaction content is loaded on demand through `MessagesController#interactions`
- The endpoint renders `app/views/messages/interactions.html.erb`
- `ModelInteraction` broadcasts Turbo stream updates for open modal content (`interactions-list-*` and `interactions-count-*`)
## Testing

```bash
bin/rails test test/models/model_interaction_test.rb
bin/rails test test/ai/unit/model_interaction_recorder_test.rb
bin/rails test test/ai/unit/client_test.rb
```
