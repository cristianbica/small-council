# Plan: Reintroduce conversation slash commands (`/advisors`, `/invite`, `/kick`)

## Type
feature

## Goal
Reintroduce slash commands in conversation composer with these behaviors:
- `/advisors` opens a modal listing advisors.
- `/invite advisor-name` adds advisor to the conversation.
- `/kick advisor-name` removes advisor from the conversation.

All command handling must have no message/runtime impact for the current turn (no persisted user command message, no AI response scheduling).

## Acceptance Criteria
1. Submitting `/advisors` from the conversation composer opens a modal with advisors for the current space.
2. Submitting `/invite advisor-name` adds the advisor as a `ConversationParticipant` with role `advisor` when valid.
3. Submitting `/kick advisor-name` removes that advisor from current conversation participants when valid.
4. Slash commands are intercepted before normal message creation, so command text is not persisted as `Message` and does not call `AI.runtime_for_conversation(...).user_posted`.
5. Existing non-command message behavior remains unchanged.

## Scope and Reuse
- Reuse and extend command pattern under `app/libs/ai/commands/`.
- Integrate command dispatch in `MessagesController#create` before `build_user_message`.
- Reuse existing modal shell pattern from `app/views/layouts/turbo_rails/frame.html+modal.erb` for a command-triggered modal render path.

## Planned Changes
1. Command services:
- Add `app/libs/ai/commands/invite_command.rb` to accept `advisor-name` (and keep `@advisor-name` compatibility).
- Add `app/libs/ai/commands/kick_command.rb` for removing participants.
- Add `app/libs/ai/commands/advisors_command.rb` for modal intent.
- Add `app/libs/ai/commands/command_router.rb` to parse slash command text and dispatch command execution.
- Add command resolver support in `app/libs/ai.rb`.

2. Controller integration:
- Update `app/controllers/messages_controller.rb`:
  - Detect slash command input before creating message records.
  - Execute command and return command-specific response.
  - For `/advisors`, render Turbo Stream replacing `page-modal` with modal content.
  - For `/invite` and `/kick`, return redirect responses without creating a message.

3. Views:
- Add `app/views/conversations/_advisors_modal_frame.html.erb` for advisors listing content in `page-modal` turbo frame.

4. Tests:
- Add tests for new command classes in `test/libs/ai/commands/`.
- Update integration expectations in `test/integration/complete_conversation_flows_test.rb` for slash commands to verify:
  - no message persisted,
  - no AI runtime enqueue,
  - participant add/remove side effects,
  - `/advisors` command response path.

## Verification
- Run targeted tests:
  - `bin/rails test test/libs/ai/commands/base_command_test.rb`
  - `bin/rails test test/libs/ai/commands/invite_command_test.rb`
  - `bin/rails test test/libs/ai/commands/kick_command_test.rb`
  - `bin/rails test test/libs/ai/commands/advisors_command_test.rb`
  - `bin/rails test test/libs/ai/commands/command_router_test.rb`
  - `bin/rails test test/libs/ai/ai_test.rb`
  - `bin/rails test test/integration/complete_conversation_flows_test.rb`
- If failures are unrelated pre-existing, report explicitly with scope.

## Risks / Notes
- Turbo response shape for command requests must preserve existing composer reset behavior.
- Keep command side effects limited to participant membership and modal display only.
