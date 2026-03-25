# Plan: Add `/memories` and `/memory ID` slash commands

## Type
feature

## Goal
Add two new conversation slash commands:
- `/memories`: open a modal listing memories for the current space (id + title).
- `/memory ID`: open a modal showing one memory.

## Acceptance Criteria
1. `/memories` validates with no args and opens modal with memory list for current conversation space.
2. `/memory ID` validates numeric id and opens modal for that memory (same account/space scoping as current conversation).
3. Invalid `/memory` usage or missing memory returns command error drawer in composer (existing behavior), no redirect in Turbo path.
4. Command autocomplete includes `/memories` and `/memory`.
5. Unknown command help text includes the two new commands.

## Planned Changes
1. New AI command handlers
- Add `app/libs/ai/commands/memories_command.rb`:
  - validate no args
  - return scoped memories relation ordered by id desc
- Add `app/libs/ai/commands/memory_command.rb`:
  - validate one numeric arg
  - find memory in `conversation.space.memories` by id

2. Modal views
- Add `app/views/conversations/_memories_modal_frame.html.erb`:
  - render id + title list
- Add `app/views/conversations/_memory_modal_frame.html.erb`:
  - render id, title, and memory content (markdown-rendered)

3. Command response routing
- Update `app/controllers/messages_controller.rb` `respond_to_command`:
  - handle `action == "memories"` with modal frame replacement
  - handle `action == "memory"` with modal frame replacement

4. Command registry UX
- Update `app/libs/ai/commands/command_router.rb` unknown-command message to include new commands.
- Update `app/views/conversations/_chat.html.erb` slash command metadata for autocomplete descriptions.

## Verification
- Editor diagnostics on changed files.
- Manual checks in a conversation:
  - `/memories` opens list modal with ids and titles.
  - `/memory <valid-id>` opens detail modal.
  - `/memory` and `/memory abc` show inline error drawer.
  - `/memory <missing-id>` shows inline error drawer.
  - Autocomplete includes the two new commands.

## Notes
- No schema changes.
- Tests deferred per current user direction.
