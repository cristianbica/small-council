# Plan: Allow changing model per-cenversation or even per-advisor in a conversation

Date: 2026-03-01

## Goal
- Allow per-conversation and per-advisor model overrides for better cost/quality control.

## Non-goals
- Overhauling provider configuration or billing logic.
- Implementing advanced auto-selection policies.

## Scope + assumptions
- Scope includes UI selection, persistence, and LLM request wiring.
- Assume models are defined in LlmModel and available to advisors.

## Steps
1. Define data model changes for conversation and advisor overrides.
2. Add UI controls for selecting a model at conversation/advisor level.
3. Update LLM request builder to respect overrides with clear precedence.
4. Add tests for override precedence and persistence.
5. Validate with a sample conversation.

## Verification
- Run model selection tests and relevant integration tests.
- Manually switch models and confirm provider requests.

## Doc impact
- Update: `.ai/docs/features/<slug>.md`

## Rollback (if applicable)
- Remove override fields and revert request builder logic.
