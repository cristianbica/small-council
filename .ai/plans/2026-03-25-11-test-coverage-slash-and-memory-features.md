# Plan: Add tests for current slash command and memory-attachment changes

## Type
feature (test coverage)

## Goal
Add/refresh tests for the currently implemented conversation slash-command system and message-type changes:
- `/advisors`, `/invite`, `/kick`, `/memories`, `/memory ID`, `/attach ID`
- `info` and `memory_attachment` message types
- AI-context inclusion/exclusion behavior
- command error drawer Turbo flow
- memory modal variant rendering path

## Acceptance Criteria
1. Unit tests exist for all AI command handlers and router parsing/unknown-command messaging.
2. Model tests verify `info` and `memory_attachment` enum behavior and context visibility rules.
3. AI task tests verify `info` messages are excluded from `RespondTask` context while `memory_attachment` messages are included.
4. Integration tests verify slash commands mutate conversation state and/or open modal responses as expected.
5. Integration tests verify command errors render composer inline error (no redirect in Turbo path).
6. `/attach` integration verifies bubble-side effects at persistence level (message type + metadata) and non-enqueue behavior.

## Planned Test Changes
1. Add command unit tests under `test/libs/ai/commands/`:
- `base_command_test.rb`
- `command_router_test.rb`
- `invite_command_test.rb`
- `kick_command_test.rb`
- `advisors_command_test.rb`
- `memories_command_test.rb`
- `memory_command_test.rb`
- `attach_command_test.rb`

2. Update `test/libs/ai/ai_test.rb`:
- command resolver coverage for newly added command classes.

3. Update `test/models/message_test.rb`:
- enum includes `info` and `memory_attachment`
- `visible_in_context` excludes info, includes memory_attachment.

4. Update `test/libs/ai/tasks/respond_task_test.rb`:
- add coverage for context filtering with `info` vs `memory_attachment`.

5. Refresh integration tests in `test/integration/complete_conversation_flows_test.rb`:
- replace stale “slash commands not parsed” expectations
- assert new slash command outcomes (participants/messages/modal/turbo status)
- assert invalid command usage returns 422 Turbo frame composer with inline error content.

6. Add focused controller test for modal variant if needed:
- verify `GET /spaces/:space_id/memories/:id` in `page-modal` frame picks modal template without full-page controls.

## Verification
Run targeted suite:
1. `bin/rails test test/libs/ai/commands`
2. `bin/rails test test/libs/ai/ai_test.rb`
3. `bin/rails test test/models/message_test.rb`
4. `bin/rails test test/libs/ai/tasks/respond_task_test.rb`
5. `bin/rails test test/integration/complete_conversation_flows_test.rb`
6. `bin/rails test test/controllers/memories_controller_test.rb` (if modal-variant assertions added)

## Notes
- Keep test fixtures deterministic and avoid relying on JS behavior.
- Scope assertions to server behavior and rendered HTML/Turbo payloads.
