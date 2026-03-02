# Plan: remove conversation advisor-count validation causing title update rollback

Date: 2026-03-02
Type: bug

## Intake summary (confirmed)
- Reported bug: `PATCH /conversations/:id` title updates can roll back because `Conversation` validation `must_have_at_least_one_advisor` runs on update.
- Confirmed scope: remove `must_have_at_least_one_advisor` validation for all cases.
- Constraint: no schema changes.
- Implementation note: use current state of `app/controllers/conversations_controller.rb` (recently edited).

## Goal
Stop update-time rollbacks triggered by advisor-count validation so conversation title updates (and other updates) persist even when a conversation has no non-scribe advisors.

## Non-goals
- No database/schema changes.
- No redesign of conversation participant flows.
- No new UX or controller behavior beyond what is necessary for this validation removal.

## Scope + assumptions
- Remove model-level validation hook and related custom method from `Conversation`.
- Keep existing `title` and `council` presence validations unchanged.
- Keep controller update logic (including `title_locked` handling) intact unless tests prove an additional minimal fix is required.

## Evidence snapshot
- Validation is defined and enforced on update in `app/models/conversation.rb` (`validate :must_have_at_least_one_advisor, on: :update`).
- Custom validator adds error `"must have at least one advisor"` in `app/models/conversation.rb`.
- `ConversationsController#update` saves assigned attributes and title lock state, so model validation failure causes rollback path in `app/controllers/conversations_controller.rb`.
- Existing tests currently encode the old invariant in `test/models/conversation_comprehensive_test.rb`.

## Implementation plan
1. Remove advisor-count validation from `Conversation` model
   - Delete `validate :must_have_at_least_one_advisor, on: :update`.
   - Delete `must_have_at_least_one_advisor` method.
   - Keep all unrelated model behaviors unchanged.
2. Update model tests that assert the removed rule
   - Replace/remove expectations that conversation is invalid without a non-scribe advisor.
   - Add/adjust expectations to reflect new valid behavior on update without advisors.
3. Add or refine controller regression coverage for reported bug
   - Ensure `PATCH /conversations/:id` title update succeeds when conversation has zero non-scribe advisors (e.g., only scribe or none).
   - Confirm `title_locked` behavior still works on successful title change.
4. Run targeted verification suite and report outcomes
   - Execute focused model + controller tests tied to this bug fix.

## Acceptance criteria
- [ ] Updating a conversation title via `PATCH /conversations/:id` succeeds when the conversation has no non-scribe advisors.
- [ ] `Conversation` model no longer enforces `must_have_at_least_one_advisor` on update (or anywhere).
- [ ] Tests no longer assert the removed advisor-count invariant and include regression coverage for the title-update path.
- [ ] No schema/db migration files are added or modified.

## Verification commands
- `bin/rails test test/models/conversation_comprehensive_test.rb`
- `bin/rails test test/controllers/conversations_controller_test.rb`
- `bin/rails test test/controllers/conversations_controller_comprehensive_test.rb`

## Doc impact
- doc impact: none (unless `.ai/docs/` currently documents the removed advisor-count invariant; if found, update that single reference only).

## Memory impact
- memory impact: none

## Approval gate
Approve this plan?
