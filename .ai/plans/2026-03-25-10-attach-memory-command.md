# Plan: Add `/attach ID` command for conversation memory attachment

## Type
feature

## Goal
Introduce `/attach ID` to attach a memory to the current conversation as a dedicated message type that:
- is included in AI context
- renders as a left-aligned chat bubble
- displays "USER attached memory" and a clickable memory title box
- opens memory modal when box is clicked

## Acceptance Criteria
1. `/attach ID` validates one numeric argument.
2. On success, creates a new message with a new message_type (attachment-specific), sender user, role user, status complete.
3. Attached memory message is included in AI context (not filtered out).
4. UI message rendering shows:
   - left-aligned bubble
   - text: `USER attached memory` (user display label)
   - clickable box with memory title
5. Clicking memory title box opens memory modal.
6. Command autocomplete and unknown-command help text include `/attach`.
7. Command errors keep existing inline drawer behavior.

## Planned Changes
1. New command handler
- Add `app/libs/ai/commands/attach_command.rb`:
  - validate usage `/attach ID`
  - find memory scoped to `conversation.space.memories`
  - create attachment message with metadata (`memory_id`, `memory_title`)
  - include structured attachment payload in message content for context relevance

2. Message model
- Update `app/models/message.rb`:
  - add enum value `memory_attachment`
  - keep `visible_in_context` excluding only `info` (attachment remains included)

3. Command registry UX
- Update `app/libs/ai/commands/command_router.rb` unknown-command help text to include `/attach`.
- Update slash command metadata in `app/views/conversations/_chat.html.erb` for autocomplete.

4. Message rendering
- Update `app/views/conversations/_message.html.erb`:
  - add dedicated branch for `message.memory_attachment?`
  - render as left-aligned bubble-style message
  - show `USER attached memory` text
  - render clickable memory title box linking to `space_memory_path` in `page-modal`

## Verification
- Editor diagnostics for changed files.
- Manual checks:
  - `/attach <valid-id>` creates one attachment message, shown in left bubble.
  - clicking attachment box opens memory modal.
  - `/attach` / `/attach abc` / missing id shows inline command error drawer.
  - autocomplete shows `/attach`.

## Notes
- No schema migration required (string enum value).
- Tests deferred per current user workflow.
