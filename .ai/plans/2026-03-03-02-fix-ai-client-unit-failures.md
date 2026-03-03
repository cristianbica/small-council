# Plan: Fix current AI client unit test failures

## Goal
Restore passing status for failing tests in `test/ai/unit/client_test.rb` without changing product behavior beyond bug fixes.

## Failing tests observed
1. `AI::ClientTest#test_chat_orders_advisor_instructions_then_council_context_then_memory_index_then_conversation_messages`
2. `AI::ClientTest#test_chat_creates_ModelInteraction_via_on_end_message_handler`

## Root causes
- The council-context test expects an old header string (`"Council and advisor context:"`) while implementation now uses `"You are a member of a council of advisors."`.
- `AI::ModelInteractionRecorder#build_chat_request_payload` attempts `JSON.parse response.raw.env.request_body` and rescues only `JSON::ParserError`; when `response.raw` is nil in tests, it raises `NoMethodError`, which prevents interaction creation.

## Changes
1. Update the council-context assertion in `test/ai/unit/client_test.rb` to match current prompt text while preserving order checks.
2. Harden `app/libs/ai/model_interaction_recorder.rb` request parsing fallback:
   - Safely attempt to read `response.raw.env.request_body` only when available.
   - Rescue `TypeError`/`NoMethodError` in addition to `JSON::ParserError` and continue to existing fallback payload builder.

## Acceptance criteria
- Both failing tests pass.
- `ModelInteraction` recording test creates one interaction again.
- No unrelated files changed.

## Verification
- `bin/rails test test/ai/unit/client_test.rb test/ai/unit/content_generator_test.rb`
- If needed, run `bin/rails test test/ai/unit/client_test.rb`

## Scope limits
- No refactor of prompt architecture or payload format.
- No changes outside recorder guard + test expectation alignment.
