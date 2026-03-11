# Conversation Title Lifecycle

Auto-title generation applies to adhoc conversations that begin with system-generated placeholder titles.

## State machine

`Conversation.title_state` values:
- `user_generated`: user explicitly set/edited title
- `system_generated`: placeholder title ready for possible auto-generation
- `agent_generating`: generation request has been claimed
- `agent_generated`: title updated by AI tool

## Trigger conditions

Auto-title generation is requested from `Conversation` callbacks when all checks pass:
- Conversation is `adhoc`
- `title_state == system_generated`
- Aggregate message content length is greater than 200 chars
- Atomic transition to `agent_generating` succeeds

## Generation path

1. `Conversation#request_auto_title_generation!` calls `AI.run` with:
- `task.type = :text`
- `prompt = "conversations/title_generator"`
- `tools = ["conversations/update_conversation"]`
- conversation context
2. `AIRunnerJob` executes the task asynchronously.
3. Tool `conversations/update_conversation` normalizes and persists title, then sets `title_state = agent_generated`.

## Failure behavior

- If enqueue/request fails, model logs warning and restores `title_state` back to `system_generated`.
- If model output is unusable, tool should not force invalid title data.

## Invariants

- Manual title edits move state to `user_generated` and should not be overwritten by later automation.
- `mark_title_generation_started!` uses a conditional update to prevent duplicate concurrent generation.
- Broadcast updates for title changes are emitted via Turbo stream in `Conversation#broadcast_title_update`.
