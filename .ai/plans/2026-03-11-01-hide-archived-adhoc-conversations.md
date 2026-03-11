# Plan: Hide Archived Adhoc Conversations By Default

Date: 2026-03-11

## Goal
Do not show archived conversations by default in the adhoc conversations list.

## Scope
- Adhoc conversation sidebar/list data source used on conversation pages.
- Adhoc index redirect behavior (when visiting `/conversations` without a council).

## Proposed Changes
1. Add a conversation scope for non-archived records:
   - `Conversation.not_archived` => `where.not(status: "archived")`
2. Update adhoc list queries in `ConversationsController` to use it:
   - `index` adhoc fallback query
   - `set_sidebar_conversations`
3. Keep all other conversation lists and archive behavior unchanged.

## Files
- `app/models/conversation.rb`
- `app/controllers/conversations_controller.rb`

## Verification
- Manual check: open adhoc conversation UI and confirm archived conversations are absent from the sidebar list.
- Manual check: visit `/conversations` and confirm redirect targets the most recent non-archived adhoc conversation.
- If all adhoc conversations are archived, confirm existing auto-create flow still works.

## Out of Scope
- New toggle/filter UI for showing archived conversations.
- Changes to council meeting conversation lists.
