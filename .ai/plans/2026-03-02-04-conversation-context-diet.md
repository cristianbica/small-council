# Plan: Conversation context diet (used vs unused fields)

Date: 2026-03-02

## Goal
Reduce unnecessary context built and passed during advisor generation while preserving current behavior for tools, usage tracking, and scribe flows.

## Why now
- `ConversationContextBuilder` currently produces a broad context hash.
- `AI::Client` and tools only consume a subset of keys directly.
- Extra context can increase object construction/query overhead and cognitive complexity.

## Non-goals
- No UI changes.
- No lifecycle-trigger changes.
- No prompt redesign beyond existing `memory_index` behavior.
- No removal of tool capabilities.

## Scope
- `app/libs/ai/context_builders/conversation_context_builder.rb`
- `app/libs/ai/content_generator.rb`
- `app/libs/ai/client.rb`
- Targeted tests in `test/ai/unit/**` and any directly affected service/job tests.

## Current usage map (from investigation)

### Directly used in advisor generation path
- `space`, `account`, `conversation`, `message` (tracking + tool context in `AI::Client`).
- `memory_index` (serialized as system context message in `AI::Client`).
- `user` / `advisor` / `conversation` / `space` (consumed by multiple tools).

### Used in scribe follow-up rendering
- `participants`, `roe_description` (in `AI::ContentGenerator#generate_scribe_followup`).

### Likely not directly consumed today in runtime path
- `related_conversations`, `available_advisors`, `conversation_thread`, `advisors`, `council`, `max_depth`, `primary_summary` (outside memory index), and possibly others built for completeness/future use.

## Strategy
Use explicit per-flow context shaping rather than one oversized shared payload.

### Option A (recommended): Per-flow minimal context hashes
1. Keep `ConversationContextBuilder` for deriving shared data, but stop passing full `ctx` blindly to `AI::Client`.
2. In `generate_advisor_response`, build `client_context` explicitly with only required keys:
   - `space`, `account`, `conversation`, `user`, `advisor`, `memory_index` (+ any mandatory tracing keys like `message` when available).
3. In `generate_scribe_followup`, continue using `participants`/`roe_description` only for prompt rendering; pass minimal execution context to `client.complete`.
4. Keep `memories` available only if a tool path still requires it (validate tool expectations first).

### Option B: Trim builder output globally
- Remove unused keys directly from `ConversationContextBuilder#build`.
- Higher risk because other call sites may implicitly rely on keys.

## Recommendation
Start with **Option A** for safety and clearer ownership. Once stable, consider Option B as a follow-up cleanup.

## Implementation steps
1. Add a small “context shaping” method in `AI::ContentGenerator`:
   - `advisor_client_context(ctx:, advisor:, conversation:, extra_context:)`.
2. Replace `context: ctx.merge(context)` in `generate_advisor_response` with the shaped hash.
3. Keep builder behavior unchanged in first pass (avoid broad breakage).
4. Add logging (debug-level) for context keys sent to `AI::Client` during rollout.
5. Optional second pass: prune builder keys that are now confirmed unused.

## Acceptance criteria
- Advisor responses still function across open/consensus/brainstorming modes.
- Tools continue to receive required context (`space`, `conversation`, `user`/`advisor`, `account`).
- `memory_index` continues to be serialized into model-visible system context.
- No regressions in scribe follow-up generation.
- Context keys sent to `AI::Client` are explicitly minimal and documented.

## Verification plan
- Unit:
  - `AI::ContentGenerator` passes only expected context keys for advisor flow.
  - `AI::Client` still serializes `memory_index` when present.
  - Tool execution tests for key context dependencies (`space`, `conversation`, `user`/`advisor`).
- Integration:
  - Post message in council meeting and adhoc conversation, verify advisor response path works.
  - Scribe follow-up still renders with participants + RoE description.
- Regression:
  - Existing `GenerateAdvisorResponseJob` tests remain green.

## Risks
- Hidden coupling: a tool or recorder might depend on a key not documented.
- Silent behavior drift if context keys are removed too aggressively.

## Mitigations
- First-pass shaping only (do not prune builder yet).
- Add tests that assert required context keys for tool-heavy scenarios.
- Roll out in two phases (shape first, prune second).

## Rollback
- Revert `ContentGenerator` to pass full `ctx.merge(context)`.
- Keep `ConversationContextBuilder` unchanged.

## Doc impact
- deferred (update `.ai/docs/features/ai-integration.md` if context contract changes are finalized).
