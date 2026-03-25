# Plan: Inline Weakest-Model Compaction Logic in compaction_required?

## Change type
bug

## Goal
Replace fixed char threshold in `ConversationRuntime#compaction_required?` with inline weakest-model-aware threshold logic, without extracting a new service.

## Scope
- In scope:
  - Update only `compaction_required?` logic in `app/libs/ai/runtimes/conversation_runtime.rb`.
  - Use involved advisors' effective models and weakest `context_window` as trigger basis.
  - Keep fallback behavior when context window/model data is missing.
  - Add concise debug logging for computed values.
  - Run targeted runtime tests and full test suite.
- Out of scope:
  - New calculator/service extraction.
  - Runtime-specific advisor set tuning beyond conversation participants.

## Implementation
1. In `compaction_required?`:
- Compute involved advisors from `@conversation.all_participant_advisors`.
- Resolve `effective_llm_model` and collect positive `context_window` values.
- Determine `weakest_context_window` from min value, fallback to 8192 tokens if missing.
- Compute trigger token budget as 70% of weakest context window.
- Estimate context tokens from message chars since last compaction via `chars / 4.0` (+ small fixed overhead).
- Return true when estimated tokens exceed trigger budget.

2. Keep as inline method logic
- No additional class extraction.

3. Verification
- `bin/rails test test/libs/ai/runtimes/conversation_runtime_test.rb`
- `bin/rails test`

## Risks and mitigations
- Risk: rough token estimation differs from provider tokenizer reality.
- Mitigation: conservative budget (70%) and fallback defaults; logging to tune later.
