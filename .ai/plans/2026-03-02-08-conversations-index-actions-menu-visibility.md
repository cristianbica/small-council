# Plan: conversations index actions menu visibility

Date: 2026-03-02
Type: bug

## Intake summary (confirmed)
- Bug: actions (3-dots) menu appears missing on `/conversations`.
- Expected: authorized users can reliably access archive/delete actions for both `adhoc` and `council_meeting` rows.
- Constraints: keep archive/delete options and authorization model unchanged; minimal scope and tests.

## Goal
Ensure users who are authorized to delete/archive can consistently see and use the conversation actions trigger on `/conversations`, including non-hover/touch scenarios.

## Non-goals
- No changes to archive/delete business rules or authorization policy.
- No redesign of conversation list layout beyond making the existing trigger reliably accessible.
- No changes outside the `/conversations` index flow unless strictly required by tests.

## Scope + assumptions
- Scope is limited to `app/views/conversations/index.html.erb` and the smallest relevant test coverage.
- Existing helper/policy checks (for delete/archive visibility) remain the source of truth.
- Current issue is caused by trigger container classes `opacity-0 group-hover:opacity-100`, which hides the trigger by default.

## Evidence snapshot
- In `app/views/conversations/index.html.erb`, the action trigger wrapper uses hover-gated visibility (`opacity-0 group-hover:opacity-100`), which can make the control effectively unavailable without hover.
- Action items (`Archive`, `Delete`) are already conditionally rendered based on existing authorization checks.

## Steps
1. Update the conversation row action-trigger visibility so it is available by default for rows where authorized actions exist, while preserving existing dropdown behavior and styling conventions.
2. Keep current conditional rendering for `Archive` and `Delete` menu items unchanged (`can_delete_conversation?`, `conversation.active?`).
3. Add/adjust targeted view or integration test(s) for `/conversations` confirming:
   - authorized users can see/use the actions trigger,
   - unauthorized users do not see archive/delete actions,
   - both `adhoc` and `council_meeting` entries still present correct actions.
4. Run focused tests only for affected coverage area.

## Acceptance checklist
- [ ] On `/conversations`, authorized users can reliably see and use the 3-dots actions trigger without requiring hover.
- [ ] Behavior applies to both `adhoc` and `council_meeting` conversation rows.
- [ ] Archive/Delete menu options remain unchanged and continue to follow existing authorization checks.
- [ ] Unauthorized users do not gain visibility/access to restricted actions.
- [ ] Only minimal, targeted code/test changes are made.

## Verification
- `bin/rails test` for the specific conversations index view/integration test file(s) touched.
- Optional quick regression: relevant conversations controller/view tests if they directly cover index row actions.

## Doc impact
- doc impact: none (bug-fix UI visibility only; no behavior/policy model change).

## Rollback (if applicable)
- Revert the small visibility/class change in `app/views/conversations/index.html.erb` and any associated tests.

## Approval gate
Approve this plan?
