# Plan: Remove finish/stop UI actions + gate scribe followup on conversation type

Date: 2026-03-01
Type: bug
Status: Completed

## Goal

1. **Remove** the `finish` and `cancel_pending` controller actions, routes, view buttons, helpers, and tests — finishing a conversation is handled exclusively through the Scribe's `FinishConversationTool`, not through a UI button.
2. **Remove** the `approve_summary`, `reject_summary`, `regenerate_summary` controller actions, routes, view partial, and tests — these are part of the same finish-via-UI flow that's being removed.
3. **Gate scribe followup** so it only fires for council meetings and only when the conversation is active.
4. **Fix** `can_delete_conversation?` nil safety bug.

## Non-goals

- Changing the `FinishConversationTool` AI tool (it stays — the Scribe uses it)
- Changing `GenerateConversationSummaryJob` (it stays — it's called by the tool via `begin_conclusion_process`)
- Changing `ConversationLifecycle#begin_conclusion_process` (it stays — called by the tool)
- Changing the scribe followup prompt content (only gating when it fires)

## Scope

### What gets REMOVED

| Component | File | What |
|-----------|------|------|
| Route: `finish` | `config/routes.rb` | `post :finish` |
| Route: `cancel_pending` | `config/routes.rb` | `post :cancel_pending` |
| Route: `approve_summary` | `config/routes.rb` | `post :approve_summary` |
| Route: `reject_summary` | `config/routes.rb` | `post :reject_summary` |
| Route: `regenerate_summary` | `config/routes.rb` | `post :regenerate_summary` |
| Controller: `finish` | `app/controllers/conversations_controller.rb` | Entire method (~lines 76-85) |
| Controller: `approve_summary` | `app/controllers/conversations_controller.rb` | Entire method (~lines 87-124) |
| Controller: `reject_summary` | `app/controllers/conversations_controller.rb` | Entire method (~lines 126-132) |
| Controller: `regenerate_summary` | `app/controllers/conversations_controller.rb` | Entire method (~lines 134-142) |
| Controller: `cancel_pending` | `app/controllers/conversations_controller.rb` | Entire method (~lines 144-164) |
| Controller: `before_action` | `app/controllers/conversations_controller.rb` | Remove `:finish, :approve_summary, :reject_summary, :regenerate_summary, :cancel_pending` from `set_conversation` only list |
| Controller: `can_manage_conversation?` | `app/controllers/conversations_controller.rb` | Private method — remove if only used by finish/cancel_pending |
| Helper: `can_finish_conversation?` | `app/helpers/application_helper.rb` | Entire method |
| View: Finish button | `app/views/conversations/show.html.erb` | The "Finish" `button_to` block |
| View: Stop button | `app/views/conversations/show.html.erb` | The "Stop" `button_to` block |
| View: Summary review partial | `app/views/conversations/_summary_review.html.erb` | Entire file (if it exists) |
| Tests: finish controller | `test/controllers/conversations_controller_comprehensive_test.rb` | 3 tests (~lines 407-458) |
| Tests: cancel_pending controller | `test/controllers/conversations_controller_test.rb` | 4 tests (~lines 472-587) |
| Tests: cancel_pending comprehensive | `test/controllers/conversations_controller_comprehensive_test.rb` | 5 tests (~lines 642-748) |
| Tests: approve_summary | `test/controllers/conversations_controller_test.rb` + comprehensive | ~5 tests |
| Tests: reject_summary | `test/controllers/conversations_controller_comprehensive_test.rb` | ~2 tests |
| Tests: regenerate_summary | `test/controllers/conversations_controller_test.rb` + comprehensive | ~5 tests |
| Tests: can_finish_conversation? | `test/helpers/application_helper_test.rb` | 4 tests (~lines 57-84) |
| Tests: integration finish/cancel | `test/integration/complete_conversation_flows_test.rb` | References to finish/cancel_pending |

### What gets CHANGED (guard clauses)

| Component | File | Change |
|-----------|------|--------|
| Scribe followup gate | `app/services/conversation_lifecycle.rb` `handle_message_solved` | Add `return unless @conversation.council_meeting?` and `return unless @conversation.active?` |
| Nil safety fix | `app/helpers/application_helper.rb` `can_delete_conversation?` | `conversation.council.user_id` → `conversation.council&.user_id` |

### What STAYS (no changes)

- `FinishConversationTool` — the Scribe's AI tool to finish conversations
- `GenerateConversationSummaryJob` — called by the tool
- `ConversationLifecycle#begin_conclusion_process` — called by the tool
- `ConversationLifecycle#begin_conclusion_process` tests in lifecycle test files
- All `FinishConversationTool` tests
- All `GenerateConversationSummaryJob` tests

## Steps

### Step 1: Remove routes
Remove `finish`, `cancel_pending`, `approve_summary`, `reject_summary`, `regenerate_summary` from `config/routes.rb`.

### Step 2: Remove controller actions + before_action references
Remove the 5 actions from `conversations_controller.rb`. Clean up `before_action :set_conversation` only list. Remove `can_manage_conversation?` if it's only used by the removed actions.

### Step 3: Remove helper
Remove `can_finish_conversation?` from `app/helpers/application_helper.rb`. Fix `can_delete_conversation?` nil safety.

### Step 4: Remove view buttons + partial
Remove "Finish" and "Stop" buttons from `show.html.erb`. Delete `_summary_review.html.erb` if it exists. Remove any rendering of that partial from `show.html.erb`.

### Step 5: Gate scribe followup
In `ConversationLifecycle#handle_message_solved`, add:
```ruby
return unless @conversation.council_meeting?
return unless @conversation.active?
```

### Step 6: Remove tests
Remove all tests for: finish action, cancel_pending action, approve_summary, reject_summary, regenerate_summary, can_finish_conversation? helper. Update integration tests that reference finish/cancel_pending.

### Step 7: Add new tests
- Test that `handle_message_solved` is a no-op for adhoc conversations
- Test that `handle_message_solved` is a no-op when conversation is concluding

## Verification
- `bin/rails test` — full suite passes with 0 failures, 0 errors
- No references to removed routes remain in non-test/non-doc files

## Doc impact
- Update `.ai/docs/features/conversations.md` — remove finish/cancel_pending routes and controller actions
- Update `.ai/docs/features/conversation-system.md` — note scribe followups are council_meeting-only
