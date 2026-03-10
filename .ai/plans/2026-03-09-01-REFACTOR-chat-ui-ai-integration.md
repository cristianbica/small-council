# Plan: Refactor Chat UI & Integrate AI Runtime Infrastructure

**Date:** 2026-03-09
**Status:** Draft (awaiting approval)
**Change Type:** Refactor
**Scope:** view ownership cleanup + Turbo broadcast contract + AI runtime integration

## Goal

Simplify the chat UI by removing threaded message display, move chat page view ownership under `conversations/show`, make `MessagesController#create` work in place without redirecting, and integrate the new AI runtime infrastructure to replace `ConversationLifecycle` and `GenerateAdvisorResponseJob`.

### Non-Goals
- Do not remove message threading data model (parent_message/replies remain for AI context)
- Do not modify prompt content (stubs already exist)
- Do not do view cleanup or deletion in this pass
- Do not touch legacy `ConversationLifecycle`
- Do not touch legacy `GenerateAdvisorResponseJob`
- Do not change `MessagesController#retry` in this pass
- Do not change conversation RoE logic or advisor selection algorithms

---

## Discovery Summary

### Current Architecture

**UI Layer:**
- `app/views/conversations/show.html.erb` owns the page, but the full chat shell lives in `app/views/shared/_chat.html.erb`
- `app/views/shared/_chat.html.erb` renders root messages via `messages.root_messages.each`
- `app/views/messages/_message_thread.html.erb` recursively renders messages with depth-based indentation (`ml-8 border-l-2`)
- Messages have parent/child relationships stored in `in_reply_to_id` foreign key
- Turbo Streams subscription on `conversation_#{conversation.id}` for real-time updates
- There are no dedicated message Turbo Stream templates today; updates come from controller/job/service broadcasts and redirects

**Controller/Data Loading:**
- `ConversationsController#show` currently excludes pending messages from the initial page load
- `MessagesController#create` still redirects back to the conversation after posting
- `MessagesController#retry` also redirects after re-enqueuing the legacy job

**Backend Orchestration (Legacy):**
- `MessagesController#create` calls `ConversationLifecycle.new(@conversation).user_posted_message(@message)`
- `ConversationLifecycle` manages:
  - Mention parsing and advisor selection
  - Pending message creation (placeholders with `status: "pending"`)
  - Turn-based advisor triggering via `GenerateAdvisorResponseJob`
  - Scribe follow-up logic for council meetings
  - Turbo Streams broadcasting via `broadcast_message`, `broadcast_placeholder`
- `GenerateAdvisorResponseJob` performs async advisor response generation using `AI::ContentGenerator`

**New Infrastructure (Already Built):**
- `AI.runtime_for_conversation(conversation)` returns appropriate runtime based on RoE
- Runtime classes: `OpenConversationRuntime`, `ConsensusConversationRuntime`, `BrainstormingConversationRuntime`
- `AI.generate_advisor_response(advisor:, message:, prompt:, async:)` triggers response generation
- `AI::Handlers::ConversationResponseHandler` processes results and notifies runtime
- Runtimes call `schedule_advisors_responses` which creates placeholder messages but **does not broadcast them**
- `Message` does not currently own its own conversation stream broadcasting

### Key Findings

1. **View Ownership Is Split:** The chat page is always `conversations/show`, but the shell lives under `shared` while message fragments live under `messages`; the partial boundary should follow page ownership more cleanly
2. **UI Threading Removal:** The recursive `_message_thread` partial should leave the rendered path; the chat list should iterate `@messages` directly in chronological order
3. **Redirect-Based Posting Is Out Of Step With Turbo:** `MessagesController#create` should respond in place so the message appears without navigation and the composer can reset cleanly
4. **Broadcast Contract Should Live With Message Records:** Using `Message` model `broadcasts_to` is a better fit than spreading message transport across controllers, services, jobs, and runtimes
5. **Pending Visibility Must Be Decided Explicitly:** If model-level create broadcasts are enabled for placeholders, the initial page query can no longer hide pending records without causing refresh/live-update mismatch
6. **Error Handling Still Needs A Runtime-Side Equivalent:** Current `ConversationLifecycle#advisor_response_error` behavior must survive the migration even if transport moves into model callbacks
7. **Retry Is Explicitly Out Of Scope:** This pass only changes `MessagesController#create`; retry stays as-is for now
8. **Target View Structure Is Now Fixed:** The destination structure for this refactor is `conversations/show` as the main chat page, `conversations/_chat` as the chat partial including the post form, and `conversations/_message` as the per-message partial

---

## Proposed Changes

### Phase 1: Re-root Chat Views Under Conversations

**Files to modify:**

1. **`app/views/conversations/show.html.erb` and new conversation-scoped partials**
   - `app/views/conversations/show.html.erb` remains the main chat view for both council and non-council conversations
   - `app/views/conversations/_chat.html.erb` becomes the chat partial and includes the post form
   - `app/views/conversations/_message.html.erb` becomes the per-message partial
   - Do not include cleanup of legacy view files in this pass

2. **Flatten message rendering**
   - Replace `messages.root_messages.each` with `messages.each`
   - Replace `render "messages/message_thread"` with `render "conversations/message"`
   - Preserve message framing needed for Turbo replacement

### Phase 2: Establish A Message Broadcast Contract

**Files to modify:**

4. **`app/models/message.rb`**
   - Add `broadcasts_to` configuration for the conversation message stream
   - Define append/replace behavior so newly created messages appear and subsequent updates replace the existing frame
   - Cover user messages, advisor placeholders, system messages, and completed advisor responses through the same model-level path

5. **Minimal handler alignment for model broadcasts**
   - Keep `AI::Handlers::ConversationResponseHandler` focused on updating message persistence/state only
   - Do not add direct Turbo stream broadcasting there if `Message` model callbacks already handle the UI update
   - Limit changes to the new runtime path only; do not touch legacy orchestration

### Phase 3: Convert Controller Responses To Turbo-Native In-Place Updates

**Files to modify:**

6. **`app/controllers/messages_controller.rb`**
   - Change `create` to avoid redirecting for Turbo requests
   - Return an in-place success response that resets the composer while relying on model broadcasts for message rows
   - Return an in-place error response with validation errors and `422 Unprocessable Entity`
   - Keep an HTML redirect fallback only for non-Turbo requests if needed by existing controller patterns

### Phase 4: Align Conversation Loading With Live Broadcast Semantics

**Files to modify:**

8. **`app/controllers/conversations_controller.rb`**
   - Revisit the `show` message query so initial page load and live broadcasts agree on pending placeholder visibility
   - Make the pending-message decision explicit in the implementation and docs

### Phase 5: Cut Over To Runtime-Based Orchestration

**Files to modify:**

9. **`app/controllers/messages_controller.rb#create`**
   - Replace `ConversationLifecycle.new(@conversation).user_posted_message(@message)`
   - With `AI.runtime_for_conversation(@conversation).user_posted(@message)`

### Phase 6: Preserve Legacy Paths Untouched

**Files to leave untouched in this pass:**

10. **`app/services/conversation_lifecycle.rb`**
   - Legacy path remains unchanged

11. **`app/jobs/generate_advisor_response_job.rb`**
   - Legacy path remains unchanged

12. **`app/controllers/messages_controller.rb#retry`**
   - Retry remains unchanged in this pass

---

## Implementation Steps

### Step 1: View Ownership Refactor (Independent)
- [ ] Make `app/views/conversations/show.html.erb` the main chat view for council and non-council conversations
- [ ] Introduce `app/views/conversations/_chat.html.erb` as the chat partial including the post form
- [ ] Introduce `app/views/conversations/_message.html.erb` as the per-message partial
- [ ] Render messages as a flat chronological list from the conversation-owned partials
- [ ] Manual test: Verify messages display in chronological order without threading
- [ ] Verify loading states, debug modals, interaction buttons still work

### Step 2: Add Model-Level Message Broadcasts (Depends on nothing)
- [ ] Add `Message` model broadcast configuration for conversation message streams
- [ ] Keep legacy transport untouched and ensure the new runtime path relies on model callbacks for message UI updates
- [ ] Verify create and update events append/replace the correct DOM targets

### Step 3: Controller Response Contract (Depends on Step 2)
- [ ] Change `MessagesController#create` to respond in place for Turbo submissions
- [ ] Reset the composer on success and return validation errors in place on failure

### Step 4: Align Initial Page Load (Depends on Step 2)
- [ ] Update `ConversationsController#show` message loading to match the chosen pending-message visibility behavior
- [ ] Confirm page refresh and live updates show the same message set

### Step 5: Runtime Integration (Depends on Steps 2-4)
- [ ] Update `MessagesController#create` to use the new runtime
- [ ] Keep `AI::Handlers::ConversationResponseHandler` limited to state updates needed for the `Message` model to broadcast replacements
- [ ] Add fallback error handling only within the new runtime/handler path used by create

### Step 6: Legacy Isolation Check
- [ ] Verify `ConversationLifecycle`, `GenerateAdvisorResponseJob`, and `MessagesController#retry` remain unchanged in this pass

### Step 7: Testing (Depends on Steps 1-5)
- [ ] Run existing test suite
- [ ] Manual test: Create conversation, post message, verify the message appears without redirect and the composer resets
- [ ] Test all three RoE modes: open, consensus, brainstorming
- [ ] Test error handling (simulate API failure)

---

## Testing Strategy

### Automated Tests

**Update existing tests:**
- `test/controllers/messages_controller_test.rb` - Replace redirect expectations with Turbo response expectations and mock new runtime calls
- `test/models/message_test.rb` or equivalent model broadcast coverage - Add message broadcast assertions
- `test/libs/ai/handlers/conversation_response_handler_test.rb` - Keep focused on message state persistence that should trigger model-level replace broadcasts
- `test/libs/ai/runtimes/conversation_runtime_test.rb` - Keep focused on sequencing and runtime behavior rather than manual broadcast calls
- conversation/integration tests - Cover in-place create, composer reset, and refresh/live-update consistency

**Test scenarios to verify:**
1. User posts message → the user message appears without navigation and the composer resets
2. Advisor placeholders appear via model broadcast in the same stream used by user messages
3. Advisor response completes → existing placeholder frame is replaced in place
4. API error occurs → message shows error state correctly after update
5. Refreshing the page shows the same set of messages that live broadcasts produced

### Manual Testing Checklist

- [ ] Open RoE: User posts with @mention → mentioned advisor responds
- [ ] Open RoE: User posts without mention (only scribe) → scribe responds
- [ ] Consensus RoE: User posts topic → scribe moderates → advisors respond
- [ ] Brainstorming RoE: User posts topic → scribe moderates → advisors respond
- [ ] Message displays in flat chronological order
- [ ] User message appears immediately without full-page navigation
- [ ] Composer clears after successful submit and preserves errors in place on failure
- [ ] Loading states appear correctly (pending → responding → complete)
- [ ] Debug modals open and show correct information
- [ ] Copy button works
- [ ] Model interactions modal loads correctly
- [ ] Page refresh matches the live-updated message list
- [ ] Error messages display correctly for the new create/runtime path

---

## Risk Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Duplicate broadcasts in the new runtime path | Medium | High | Keep the handler state-focused and avoid adding direct Turbo broadcasts where `Message` callbacks already cover the same lifecycle events |
| Missing broadcasts causing UI desync | Medium | High | Add comprehensive broadcasting tests and verify the model broadcast contract covers create and update events |
| Pending-message visibility mismatch | Medium | High | Decide explicitly whether pending placeholders are visible on refresh and align `ConversationsController#show`, broadcasts, tests, and docs |
| Composer state not resetting after create | Medium | Medium | Make the controller response contract explicit for Turbo success and validation failure paths |
| Race condition: placeholder frame not exist on update | Medium | Medium | Ensure create events append before update events replace; verify order of operations in integration tests |
| Error handling gaps | Medium | High | Port all error handling from `ConversationLifecycle` and `GenerateAdvisorResponseJob`; add handler tests |
| RoE mode behavior changes | Low | High | Preserve existing logic in runtime classes; only add broadcasting, don't change flow |
| Turbo Streams subscription mismatch | Low | Medium | Keep subscription name consistent: `"conversation_#{conversation.id}"` |

### Rollback Plan

If issues are detected:
1. Revert `MessagesController#create` to use `ConversationLifecycle`
2. Revert `MessagesController#retry` to use `GenerateAdvisorResponseJob`
3. UI changes are backward-compatible (threaded partial still exists, just not used)

---

## Migration Path

### Phase A: Feature Flag (Optional but Recommended)
If the system supports feature flags:
1. Add `use_new_runtime` flag to conversation or user
2. Gate runtime selection in controller: `if use_new_runtime? AI.runtime_for_conversation else ConversationLifecycle`
3. Enable for specific conversations/users first
4. Remove flag after verification

### Phase B: Direct Cutover (If No Feature Flags)
Given this is a refactor (not new feature) and test coverage exists:
1. Make changes in development branch
2. Run full test suite
3. Manual testing on staging
4. Deploy with monitoring for conversation errors
5. Quick rollback plan ready via git revert

---

## File-by-File Change Summary

| File | Change Type | Lines | Description |
|------|-------------|-------|-------------|
| `app/views/conversations/show.html.erb` | Modify | TBD | Main chat view for both council and non-council conversations |
| `app/views/conversations/_chat.html.erb` | Add/Modify | TBD | Chat partial including the post form |
| `app/views/conversations/_message.html.erb` | Add/Modify | TBD | Per-message partial used by the chat view |
| `app/controllers/conversations_controller.rb` | Modify | TBD | Align initial message loading with broadcast semantics |
| `app/models/message.rb` | Modify | TBD | Add model-level Turbo broadcast contract |
| `app/libs/ai/runtimes/conversation_runtime.rb` | Modify | TBD | Keep runtime focused on sequencing/persistence, not primary UI transport |
| `app/libs/ai/handlers/conversation_response_handler.rb` | Modify | TBD | Keep handler limited to message state updates that trigger model callbacks |
| `app/controllers/messages_controller.rb` | Modify | TBD | Non-redirecting Turbo create and new runtime integration |
| `test/controllers/messages_controller_test.rb` | Modify | TBD | Replace redirect assertions with Turbo response assertions |
| `test/models/message_test.rb` | Modify/Add | TBD | Cover model broadcast behavior |
| `.ai/docs/features/conversations.md` | Modify | TBD | Update conversation flow and pending visibility behavior |
| `.ai/docs/ai-diagram.md` | Modify | TBD | Update architecture away from legacy lifecycle/job broadcast ownership |

---

## Open Questions

1. **Error Recovery:** Should we add automatic retry logic in the new handler (like the job's idempotency), or keep it manual via the retry button?
   - *Recommendation:* Start with manual retry to match current behavior; add automatic retry in future iteration

2. **Pending Placeholder Visibility:** Should pending advisor placeholders become visible immediately, including after a page refresh, once `Message` owns create broadcasts?
   - *Recommendation:* Yes. It is the simplest and most coherent contract, but it does change current behavior and should be documented and tested explicitly

3. **Controller Success Response Shape:** Should `create` return a Turbo Stream that resets the composer, or rely on a no-content response and let broadcasts handle everything?
   - *Recommendation:* Return a Turbo Stream that resets the composer; a pure no-content response leaves form state handling underspecified

4. **Handler Failure Path:** If the new runtime path reports an error result, should `AI::Handlers::ConversationResponseHandler` also update the message into an error state so the `Message` model can broadcast the replace?
   - *Recommendation:* Yes. Keep that logic state-oriented only and do not add direct Turbo broadcasting there

---

## Doc Impact

- **Updated** - Behavior and architecture docs should be updated because message transport ownership and pending-message visibility will change.
- Minimum expected updates: `.ai/docs/features/conversations.md` and `.ai/docs/ai-diagram.md`

---

## Success Criteria

1. Messages display in flat chronological order (no threading/indentation)
2. The chat page structure is owned by `app/views/conversations/show.html.erb`, `app/views/conversations/_chat.html.erb`, and `app/views/conversations/_message.html.erb`
3. User messages appear without redirect and the composer resets in place
4. `Message` model broadcasts drive message creation and updates for the chat stream
5. All three RoE modes work correctly with the new runtime
6. Error handling works correctly for the new create/runtime path
7. Page refresh shows the same message set produced by live updates
8. All existing tests pass
9. No regression in loading states, debug modals, or interaction buttons

---

**Approve this plan?**
Once approved, implementation can proceed via the `.ai/workflows/change.md` workflow with the `refactor` change type.
