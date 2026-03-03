# Model Interactions

Records every LLM API request/response for AI-generated messages and exposes them through a per-message modal in the conversation UI.

## Overview

When an advisor generates a response, RubyLLM event handlers (`on_end_message`, `on_tool_call`, `on_tool_result`) capture each LLM round-trip. An `AI::ModelInteractionRecorder` writes each interaction to the `ModelInteraction` table with full, untruncated payloads. Both chat completions and tool executions are recorded as separate interaction types.

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

## Recording via Event Handlers

Recording uses `AI::ModelInteractionRecorder` (`app/libs/ai/model_interaction_recorder.rb`) wired into RubyLLM's native event handler callbacks. Context flows via closure — the `recorder` object is captured in the handler blocks, with no thread-locals needed.

The private method `register_interaction_handler` in `AI::Client` wires up 3 handlers on the chat instance:

- **`on_end_message`** → `recorder.record_chat(chat:, response:)` — only records `role: :assistant` messages
- **`on_tool_call`** → `recorder.record_tool_call(tool_call)` — stashes call data and starts a timer
- **`on_tool_result`** → `recorder.record_tool_result(result)` — pairs with the pending call and writes the record

```ruby
recorder = AI::ModelInteractionRecorder.new(message_id: message.id, account_id: account.id)
recorder.start_timing
chat.on_end_message { |response| recorder.record_chat(chat: chat, response: response) }
chat.on_tool_call { |tool_call| recorder.record_tool_call(tool_call) }
chat.on_tool_result { |result| recorder.record_tool_result(result) }
response = ruby_llm_chat.complete
```

Key behaviors:
- Only records when both `message_id` and `account_id` are present (advisor responses only)
- Chat interactions record `role: :assistant` messages; tool interactions record tool call/result pairs
- Rescue-and-log pattern — recording failures never break AI responses
- **No truncation** — full system prompt, messages, and responses stored
- Sequence auto-determined from existing interaction count per message
- Duration calculated from recorder timing (chat) or per-tool-call timer (tool)

## Payload Formats

**request_payload:**
```json
{
  "model": "gpt-4",
  "provider": "openai",
  "temperature": 0.7,
  "system_prompt": [{"type": "text", "content": "..."}],
  "messages": [{"role": "user", "parts": [{"type": "text", "content": "..."}]}]
}
```

**response_payload:**
```json
{
  "messages": [{"role": "assistant", "parts": [{"type": "text", "content": "..."}]}],
  "input_tokens": 100,
  "output_tokens": 50,
  "model": "gpt-4-0613"
}
```

## UI

- **Icon**: Terminal/code icon next to advisor-owned messages, including pending placeholders.
- **Modal size**: approximately `80vw` width and `95vh` height.
- **Async modal loading**: interaction content is fetched on-demand from `MessagesController#interactions` when modal opens.
- **Live updates**: `ModelInteraction` broadcasts Turbo Stream updates for open modal content (`interactions-list-*` and `interactions-count-*`).
- **Section layout**:
  - Chat/system→model interactions: `Request`, `Request Tools`, `Response`
  - Tool interactions: `Request`, `Response`

## Design Decisions

| Decision | Rationale |
|---|---|
| Event-handler recording | RubyLLM's native callbacks; no external dependencies |
| Closure-based context | Recorder captured in closure; scoped to single chat call |
| Dual interaction types | chat for LLM completions, tool for tool executions |
| Full content (no truncation) | Complete payloads stored for debugging |
| JSONB for request/response | Schemas vary by provider and evolve; GIN indexed for queryability |
| No encryption on payloads | Content already encrypted at message level; JSONB encryption prevents GIN indexing |
| Rescue-and-log | Same pattern as `track_usage`; recording must never break AI responses |
| On-demand interactions endpoint | Avoids eager rendering of large JSON payloads during initial chat load |
| Turbo Stream modal updates | Enables live interaction visibility while modal is open |

## Testing

```bash
bin/rails test test/models/model_interaction_test.rb                   # model tests
bin/rails test test/ai/unit/model_interaction_recorder_test.rb         # 17 recorder tests
bin/rails test test/ai/unit/client_test.rb                             # event-handler integration tests
```
