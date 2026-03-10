# Plan: Conversation AI Runtime Slice

Date: 2026-03-08
Status: proposed
Change type: refactor
Scope: AI namespace only

## Goal

- Build the missing AI runtime pieces for conversation responses inside `app/libs/ai/`.
- Keep product orchestration in the existing job and lifecycle code for now.
- Stop before rewiring `GenerateAdvisorResponseJob` or other non-`AI::` callers.

## In scope

- Add `AI::Contexts::ConversationContext`.
- Add `AI::Tasks::RespondTask`.
- Add `AI::Agents::AdvisorAgent`.
- Add a tracker for recovering `ModelInteraction` persistence on the new runtime path.
- Add conversation-oriented handlers needed for post-run application behavior.
- Add any prompt files needed by the new agent/task pair.
- Add minimal tests for these new runtime objects.

## Out of scope

- No changes to `GenerateAdvisorResponseJob`.
- No changes to `ConversationLifecycle` behavior.
- No changes to `MessagesController` retry flow.
- No migration of conversation title generation.
- No removal of `AI::ContentGenerator` in this step.

## Constraints

- Preserve the current runtime shape already established for utility generation.
- Keep public APIs literal and explicit.
- Do not expand into tool architecture redesign.
- Prefer parity with current conversation behavior over cleanup.

## Implementation steps

### 1. Add `ConversationContext`

- Introduce a typed context object that wraps conversation-specific records and exposes the model selection needed for response generation.
- Use the current conversation/advisor/account data model rather than inventing a broader abstraction.
- Keep the object small: record access, derived helpers, and model resolution only.

### 2. Add `AdvisorAgent`

- Introduce the first conversation-oriented agent class.
- Make it responsible for system prompt assembly for both normal advisors and scribe advisors.
- Reuse current advisor record data and existing prompt ownership patterns.

### 3. Add `RespondTask`

- Introduce a task that prepares a conversation response request using the conversation context and agent.
- Keep chat preparation limited to:
  - adding agent instructions
  - attaching any needed messages
  - preserving the runner/task contract already used by `TextTask`
- Avoid moving persistence or broadcasting concerns into the task.

### 4. Add conversation tracker

- Introduce a runner-compatible tracker that restores `ModelInteraction` persistence for the new runtime path.
- Keep it narrowly focused on parity with the current `AI::Client` event-based recording behavior.
- Use existing `ModelInteraction` storage semantics rather than redesigning the schema or recorder model.

### 5. Add handlers

- Introduce the conversation handlers needed to apply completed results and surfaced failures after a run.
- Keep handlers responsible for side effects such as mapping the result back onto the message shape expected by the current app.
- Keep job/lifecycle ownership outside the handler layer for now.

### 6. Add prompt assets

- Add the minimal prompt files required for the new conversation agent/task path.
- Keep prompts aligned with the current advisor vs scribe behavior instead of redesigning tone or policy.

### 7. Add focused tests

- Cover `ConversationContext` model resolution.
- Cover `AdvisorAgent` prompt selection/assembly.
- Cover `RespondTask` request preparation at the unit level.
- Cover the new tracker behavior for `ModelInteraction` recovery.
- Cover the new handlers at the unit level.
- Do not add end-to-end job/lifecycle tests in this slice.

## Acceptance criteria

- The new AI runtime classes for conversations exist and load cleanly.
- They can express a conversation response run without going through `AI::ContentGenerator` internals.
- The runtime has a clear path to persist `ModelInteraction` records for conversation runs.
- The runtime has handlers for applying success and failure results.
- No job/controller/lifecycle behavior changes are introduced in this step.
- Focused AI unit tests pass.

## Verification

- Run the smallest relevant AI unit test files for the new classes.
- Run any existing nearby AI tests that validate the shared runner/task/agent contracts if touched.

## Follow-up after this plan

- Wire `GenerateAdvisorResponseJob` to `AI::Runner` using these new AI runtime pieces.
- Move success/error message application and broadcast behavior behind a conversation handler or equivalent thin adapter.
- Decommission the legacy conversation path in `AI::ContentGenerator` once callers are migrated.
