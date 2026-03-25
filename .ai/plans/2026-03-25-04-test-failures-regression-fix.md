# Plan: Fix Current Test Regressions

## Change type
bug

## Goal
Resolve the current suite regressions introduced by recent AI client/retry behavior changes while preserving Anthropic support.

## Failing areas
- `test/libs/ai/client_test.rb`
  - `test_connection` contract mismatch (expects `RubyLLM.configure` + `RubyLLM.chat` path and `{ success: true, model: ... }` payload)
  - `find_test_model_id` crashes when `RubyLLM.models.by_provider` returns an Array
  - default fallback expectation mismatch
- `test/libs/ai/handlers/conversation_response_handler_test.rb`
  - retry path status behavior mismatch

## Scope
- In scope:
  - Update `AI::Client.test_connection` to satisfy test contract and avoid network-dependent behavior in tests.
  - Make `AI::Client.find_test_model_id` robust for both enumerable adapters and plain arrays.
  - Keep Anthropic config support in `configure_provider`.
  - Restore retry status behavior in `ConversationResponseHandler` expected by current tests.
- Out of scope:
  - Refactoring message retry semantics beyond compatibility with current tests.

## Implementation
1. `app/libs/ai/client.rb`
- Use `RubyLLM.configure` and `RubyLLM.chat` in `test_connection`.
- Return `{ success: true, model: response.model }` on success.
- Keep error payload behavior unchanged.
- Update `find_test_model_id`:
  - accept either array-like and provider collection objects,
  - prefer `free?` model when available,
  - fallback to first model,
  - fallback default model by provider type.
- Set default fallback model for OpenAI-compatible types to `gpt-3.5-turbo` (to match tests), Anthropic fallback remains Claude.

2. `app/libs/ai/handlers/conversation_response_handler.rb`
- Restore retry path update to increment `retry_count` without forcing status change before `retry!`.
- Keep max retries at 2 to match tests.

3. Verification
- `bin/rails test test/libs/ai/client_test.rb test/libs/ai/handlers/conversation_response_handler_test.rb`
- `bin/rails test` (full suite)

## Risks and mitigations
- Risk: fallback model defaults may not be ideal for runtime costs.
- Mitigation: scope this fix to restore passing tests; runtime tuning can be a separate planned change.
