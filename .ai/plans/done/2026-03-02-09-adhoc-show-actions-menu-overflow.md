# Plan: adhoc show actions menu overflow

Date: 2026-03-02
Type: bug

## Intake summary (confirmed)
- Issue: in council conversation lists, row actions menu renders correctly.
- Issue: in adhoc conversation list shown on `conversations#show`, the actions menu renders offside and introduces horizontal scrolling.
- Constraints: keep archive/delete semantics and authorization unchanged; keep scope minimal to view/CSS classes and focused tests.

## Goal
Fix positioning/layout of the adhoc sidebar row actions dropdown in `conversations#show` so opening the menu does not cause horizontal overflow.

## Non-goals
- No changes to controller/model authorization logic (`can_delete_conversation?`, `deletable_by?`).
- No UX redesign of conversation rows beyond minimal class/structure alignment.
- No changes to council list behavior outside regression checks.

## Scope + assumptions
- Primary scope: `app/views/conversations/show.html.erb` (desktop and mobile sidebar list rows).
- Optional minimal style class adjustment only if required in existing Tailwind/DaisyUI primitives.
- Focused test scope: existing conversations/councils controller rendering assertions that cover actions trigger and action labels.
- Assumption: overflow is caused by dropdown placement within full-width `menu` row structure in show sidebar, not backend data.

## Evidence snapshot
- `app/views/councils/show.html.erb` renders conversation rows with actions outside link body and does not report overflow in the issue.
- `app/views/conversations/show.html.erb` sidebar rows place `dropdown dropdown-end` inside `menu` row content where row width is tightly constrained (`w-80` sidebar).
- `ConversationsController#set_sidebar_conversations` confirms this issue is isolated to adhoc `show` sidebar list (`@conversation.adhoc?`).

## Implementation steps (for approved build phase)
1. Adjust sidebar row structure/classes in `app/views/conversations/show.html.erb` so each row keeps link content width-constrained while dropdown anchors within row bounds (desktop first, mirror on mobile drawer if same pattern applies).
2. Keep action item conditions exactly as-is (`conversation.active? && can_delete_conversation?` for Archive; `can_delete_conversation?` for Delete).
3. Add/adjust focused rendering test(s) to assert adhoc `show` includes actions trigger and expected action labels under authorized conditions, and no action labels under unauthorized conditions.
4. Run only targeted test files related to conversation/council controller rendering and menu visibility.

## Acceptance checklist (mapped to issue)
- [ ] In adhoc `conversations#show` sidebar list, opening row actions does not introduce horizontal page/sidebar scrolling.
- [ ] Actions menu remains visually anchored inside the sidebar/list bounds (no offside render).
- [ ] Archive/Delete visibility semantics remain unchanged from current permission rules.
- [ ] Council conversation list behavior remains unchanged.
- [ ] Changes remain minimal and limited to view/CSS classes plus focused tests.

## Verification
- Targeted tests (expected):
  - `bin/rails test test/controllers/conversations_controller_test.rb`
  - `bin/rails test test/controllers/councils_controller_test.rb`
- Manual QA (expected during implementation):
  - Open adhoc `conversations#show`, trigger row actions in sidebar (desktop and mobile drawer), verify no horizontal overflow.

## Doc impact
- doc impact: none (layout bug fix only; no user-facing behavior or policy change).

## Approval gate
Approve this plan?
