# Plan: ModelInteraction via OpenTelemetry

Date: 2026-03-01
Type: refactor
Status: Completed

## Goal

Replace the custom `record_interaction` method in `AI::Client#chat` with OpenTelemetry instrumentation using `opentelemetry-instrumentation-ruby_llm`. Write OTel spans to the `ModelInteraction` table via a custom SpanProcessor so the UI modal shows full, untruncated request/response data for debugging.

## Why

The current `record_interaction`:
- Truncates messages to 500 chars and responses to 1000 chars — loses debug info
- Records one interaction per `AI::Client#chat` call — misses individual tool call round-trips
- Is manually wired — duplicates what OTel can capture automatically

The OTel gem instruments `RubyLLM::Chat#ask` — each individual LLM round-trip including tool call loops gets its own span. With `capture_content: true`, we get full system prompts, input messages, and output messages untruncated.

## Non-goals

- Shipping traces to an external backend (can add later)
- Changing the `UsageRecord` / `track_usage` system
- Modifying the OTel gem itself
- Streaming support (gem doesn't support it yet)

## Architecture

```
AI::Client#chat
  → sets OTel baggage: message_id, account_id
  → calls ruby_llm_chat.complete
    → RubyLLM::Chat#ask (OTel-instrumented, creates span)
      → may call #ask again for tool loops (each gets its own span)
  → SpanProcessor#on_finish receives each span
    → reads baggage for message_id, account_id
    → writes ModelInteraction record with full payloads
  → remove record_interaction call (OTel handles it)
```

Key insight: OTel Baggage propagates through the call stack. We set `message_id` and `account_id` as baggage before calling `complete`, and the SpanProcessor reads it when processing spans.

## Steps

### Step 1: Add gems

Add to Gemfile:
```ruby
gem "opentelemetry-sdk"
gem "opentelemetry-instrumentation-ruby_llm"
```

Run `bundle install`.

### Step 2: Create OTel initializer

Create `config/initializers/opentelemetry.rb`:
- Configure OTel SDK
- Register ruby_llm instrumentation with `capture_content: true`
- Register custom `ModelInteractionSpanProcessor`
- Use a no-op or simple log exporter (no external backend)

### Step 3: Create SpanProcessor

Create `app/libs/ai/model_interaction_span_processor.rb`:
- Implements `OpenTelemetry::SDK::Trace::SpanProcessor` interface
- `on_finish(span)`: filters for `gen_ai.operation.name == "chat"` spans only
- Reads span attributes to build `request_payload` and `response_payload`
- Reads OTel baggage for `message_id` and `account_id`
- Creates `ModelInteraction` record
- Rescue all errors (never break the span pipeline)

Span attributes available (with `capture_content: true`):
- `gen_ai.request.model`, `gen_ai.response.model`, `gen_ai.provider.name`
- `gen_ai.request.temperature`
- `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`
- `gen_ai.system_instructions` (full system prompt as JSON)
- `gen_ai.input.messages` (full input messages as JSON)
- `gen_ai.output.messages` (full response as JSON)
- Span start/end timestamps for duration

### Step 4: Set OTel baggage in AI::Client#chat

In the non-streaming path of `AI::Client#chat`:
- Before calling `ruby_llm_chat.complete`, set baggage entries for `app.message_id` and `app.account_id`
- Use `OpenTelemetry::Baggage` to propagate context
- Remove the `record_interaction` call and the `started_at`/`duration_ms` timing code

### Step 5: Remove `record_interaction` method

Delete the `record_interaction` private method from `AI::Client`. The SpanProcessor now handles this.

### Step 6: Update ModelInteraction schema (no migration needed)

The existing schema works. The JSONB columns (`request_payload`, `response_payload`) can store the OTel-formatted data. The only difference is content won't be truncated anymore.

Update `request_payload` format to use OTel attribute names:
```json
{
  "gen_ai.request.model": "gpt-4",
  "gen_ai.provider.name": "openai",
  "gen_ai.request.temperature": 0.7,
  "gen_ai.system_instructions": "...",
  "gen_ai.input.messages": [...],
  "tools": [...]
}
```

Update `response_payload` format:
```json
{
  "gen_ai.output.messages": [...],
  "gen_ai.usage.input_tokens": 100,
  "gen_ai.usage.output_tokens": 50,
  "gen_ai.response.model": "gpt-4"
}
```

### Step 7: Update UI modal

Update `_message_thread.html.erb` and `_message.html.erb` to display the new payload format. The structure changes slightly (OTel attribute names instead of custom keys), but the modal layout stays the same.

### Step 8: Update tests

- Remove `record_interaction` tests from `test/ai/unit/client_test.rb`
- Add tests for `ModelInteractionSpanProcessor`:
  - Creates ModelInteraction from a chat span with baggage
  - Skips non-chat spans (tool execution spans)
  - Handles missing baggage gracefully (no message_id → no record)
  - Handles errors without crashing
- Add integration test: OTel span → SpanProcessor → ModelInteraction → UI modal data
- Ensure existing tests pass with OTel SDK loaded (may need test helper setup)

### Step 9: Update docs

- Update `.ai/docs/features/model-interactions.md`
- Create `.ai/docs/patterns/opentelemetry.md` — document OTel setup
- Update `.ai/MEMORY.md` with OTel gems and patterns

## Verification

- `bin/rails test` — 0 failures, 0 errors
- ModelInteraction records contain full untruncated payloads
- UI modal displays correct data with new payload format
- No truncation of message content or response content

## Rollback

1. Remove OTel gems from Gemfile
2. Delete `config/initializers/opentelemetry.rb`
3. Delete `app/libs/ai/model_interaction_span_processor.rb`
4. Restore `record_interaction` method in `AI::Client`
5. Restore `record_interaction` call in `AI::Client#chat`
6. `bundle install`
