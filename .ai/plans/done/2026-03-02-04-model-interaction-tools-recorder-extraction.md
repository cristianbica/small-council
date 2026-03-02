# Plan: Fix missing `tools` in model interaction request payload (recorder-side)

Date: 2026-03-02
Workflow: change (bug)

## Goal
- Restore `request_payload["tools"]` for chat interactions by extracting tools from `RubyLLM::Chat` inside `AI::ModelInteractionRecorder`, using the existing `record_chat(chat:, response:)` path.

## Non-goals
- No DB schema or migration changes.
- No pre-send snapshot architecture or broader payload-capture refactor in `AI::Client`.
- No change to tool-call / tool-result interaction recording behavior.

## Confirmed constraints
- Source of truth for this bug fix: `RubyLLM::Chat` object passed to `ModelInteractionRecorder`.
- `tools` shape must be model-visible schema only:
  - `name`
  - `description`
  - `parameters`
- Keep scope minimal and localized.

## Scope + assumptions
- Scope is limited to recorder payload building and recorder-focused unit tests.
- Assume tool definitions are accessible from the chat instance at record time (direct accessor and/or stable instance variable paths).
- If a tool definition cannot be normalized to model-visible schema, it is skipped rather than persisted with internal fields.

## Files to update (exact)
- `app/libs/ai/model_interaction_recorder.rb`
  - Add recorder-side extraction/normalization for tools from `chat`.
  - Include `tools` in `build_chat_request_payload` only when present.
- `test/ai/unit/model_interaction_recorder_test.rb`
  - Add/adjust tests asserting:
    - `request_payload["tools"]` is present when chat has tools.
    - each tool includes only `name`, `description`, `parameters`.
    - no internal/runtime fields leak into payload.
- `.ai/docs/features/model-interactions.md`
  - Update request payload format and behavior notes to include `tools` sourced from chat, model-visible schema only.

## Implementation steps
1. Add a private recorder helper to read tool definitions from `chat` and normalize them to `{ name:, description:, parameters: }`.
2. Update `build_chat_request_payload` to merge normalized `tools` into chat request payload when non-empty.
3. Add focused recorder unit coverage for presence + schema filtering (including regression for no tools).
4. Update feature doc section for request payload shape and recording behavior.

## Verification
- `bin/rails test test/ai/unit/model_interaction_recorder_test.rb`
- Optional confidence check (if recorder tests touch shared client mocks):
  - `bin/rails test test/ai/unit/client_test.rb`

## Risks / mitigations
- Risk: RubyLLM chat tool internals differ across versions.
  - Mitigation: keep extractor defensive, normalize only known model-visible fields, default to omitting `tools` if unavailable.
- Risk: accidental payload shape drift.
  - Mitigation: explicit unit assertions on exact allowed keys per tool.

## Doc impact
- doc impact: updated (`.ai/docs/features/model-interactions.md`)

## Memory impact
- memory impact: none

Approve this plan?