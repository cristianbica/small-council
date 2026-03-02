# Plan: Conversation UI flash cleanup, visibility removal, smart scroll

Date: 2026-03-01

## Goal
- Remove success flashes for conversation creation and message posting, remove conversation visibility across UI/tools/DB (if present), and implement smart autoscroll in chat view (only when user is at bottom).

## Non-goals
- No redesign of chat UI, message rendering, or Turbo stream architecture beyond scroll logic.
- No changes to council visibility unless explicitly required by existing conversation visibility usage.

## Scope + assumptions
- Evidence: conversation creation/flash behavior in `app/controllers/conversations_controller.rb`; message posting flash in `app/controllers/messages_controller.rb`; chat scroll logic in `app/javascript/controllers/conversation_controller.js`; message frame load hook in `app/views/messages/_message.html.erb`.
- Assumption: No `conversations.visibility` column exists in current schema (not present in `db/schema.rb`); if a visibility field exists elsewhere (pending migration/branch), it must be removed from model/DB/UI/tools/tests.
- Conversations UI surfaces are `app/views/conversations/index.html.erb`, `app/views/conversations/show.html.erb`, `app/views/conversations/new.html.erb`, and the conversation layout flash block in `app/views/layouts/conversation.html.erb`.

## Steps
1. **Remove success flashes for conversation creation**
   - Update `ConversationsController` success redirects (`create_council_meeting`, `create_adhoc_conversation`, `quick_create`, `auto_create_conversation`) to omit `notice` while preserving error alerts.
   - Scan any tests expecting these flash notices and update assertions accordingly.
2. **Remove success flash when posting a message**
   - Update `MessagesController#create` success redirect to omit `notice` while preserving validation errors and access alerts.
   - Update any controller/system tests that assert the flash.
3. **Remove conversation visibility everywhere (conditional)**
   - Re-scan for any `Conversation` visibility usage in models, controllers, views, AI tools, or tests.
   - If a visibility attribute exists:
     - Remove it from `Conversation` model (enum/validation/logic), forms/filters, and any AI tools that expose it.
     - Add a migration to drop the visibility column/index and update any backfill/migration docs.
     - Update tests and fixtures accordingly.
   - If no visibility attribute exists (current state), document as no-op and ensure no UI/tool surfaces reference it.
4. **Implement smart autoscroll in chat view**
   - Enhance `conversation_controller.js` to track whether the user is at (or near) the bottom of the messages container (e.g., within a small pixel threshold).
   - On `messageRendered`, only call `scrollToBottom()` when the user is currently at the bottom.
   - Keep initial load behavior consistent (likely scroll to bottom once on connect), but avoid forcing scroll after user scrolls upward.
   - Add/adjust any data attributes or event bindings required to detect scroll position.

## Verification
- Automated:
  - `bin/rails test test/controllers/conversations_controller_test.rb` (or nearest matching tests)
  - `bin/rails test test/controllers/messages_controller_test.rb` (or nearest matching tests)
  - Any system tests that cover conversation creation/chat posting if they exist.
- Manual:
  - Create a new conversation via council and adhoc flows: confirm no success flash appears.
  - Post a message in chat view: confirm no flash appears.
  - Scroll up in a long conversation, wait for incoming message (Turbo stream): verify the scroll position remains unchanged unless already at the bottom.
  - Stay at bottom: verify incoming messages auto-scroll.
- Migration (if applicable): `bin/rails db:migrate` and verify schema change.

## Doc impact
- Update: `.ai/docs/features/data-model.md` if a conversation visibility field is removed; otherwise doc impact: none.

## Rollback (if applicable)
- Revert controller changes to restore flashes if needed.
- Revert scroll logic changes in `conversation_controller.js`.
- If a visibility column is dropped, restore via inverse migration (add column back with prior defaults/indexes).
