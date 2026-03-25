# Plan: Add `info` message type for invite/kick system notices

## Type
feature

## Goal
Introduce a new chat-visible `info` message type used for slash command side effects (`/invite`, `/kick`) with these rules:
- `message_type`: `info`
- `role`: `system`
- `sender`: current user
- Display: centered, simple, no bubble, no avatar
- AI context: excluded (not passed to model prompts)

## Acceptance Criteria
1. Message model supports `message_type: "info"`.
2. `/invite` creates an info message with content: `NAME added ADVISOR`.
3. `/kick` creates an info message with content: `NAME removed ADVISOR`.
4. Info messages are rendered centered without avatar and without chat bubble styling.
5. Info messages are excluded from AI context assembly.

## Planned Changes
1. Model + context filtering
- Update `app/models/message.rb`:
  - Add `info` to `message_type` enum.
  - Add scope/helper for AI-visible context messages (exclude `info`).
- Update `app/libs/ai/tasks/respond_task.rb`:
  - Build context from non-`info` complete chronological messages.

2. Invite/kick command side effects
- Update `app/libs/ai/commands/invite_command.rb` and `app/libs/ai/commands/kick_command.rb`:
  - After successful participant mutation, create conversation message with:
    - `sender: user`
    - `role: "system"`
    - `message_type: "info"`
    - `status: "complete"`
    - content format exactly as requested.

3. Chat rendering
- Update `app/views/conversations/_message.html.erb`:
  - Add dedicated markup branch for `message.info?`.
  - Render as centered, minimal line/text, no avatar, no bubble.
  - Keep existing rendering unchanged for all other message types.

## Verification
- Run editor diagnostics for changed files.
- Manual local check in conversation UI:
  - `/invite advisor-name` produces centered info message.
  - `/kick advisor-name` produces centered info message.
  - Advisors still update in header badges.
  - Normal user/advisor message display unchanged.

## Notes
- No schema migration is required because `message_type` is a string enum.
- Tests are intentionally deferred per current user request.
