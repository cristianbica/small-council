# Plan: ask_advisor attribution and pending-state bug fix

Date: 2026-03-02
Type: bug

## Objective
- Fix `ask_advisor` message creation so tool/system-generated messages are not persisted as user-authored messages.
- Fix `ask_advisor` enqueue flow so `GenerateAdvisorResponseJob` executes instead of skipping for non-pending messages.
- Preserve existing UI behavior, with only corrected attribution/processing flow.

## Evidence snapshot
- Confirmed bug evidence exists for conversation 22 (tool/system message persisted as user).
- Current `ask_advisor` implementation creates message with `role: "user"` and `status: "complete"`, then enqueues `GenerateAdvisorResponseJob`.
- `GenerateAdvisorResponseJob` skips unless message `pending?`, which causes ask-advisor-created jobs to skip.

## In scope
- `ask_advisor` message persistence and enqueue behavior.
- Regression tests covering the `ask_advisor` path and job execution preconditions.
- Minimal touch to existing tests where expectations currently encode incorrect behavior.

## Out of scope
- Any UI redesign or flow expansion.
- Any change to unrelated conversation lifecycle behavior.
- Data migration/backfill for historical records.

## Explicit non-goals
- No historical data backfill in this change (fix forward only).

## Concrete file targets
- `app/libs/ai/tools/conversations/ask_advisor_tool.rb`
- `app/jobs/generate_advisor_response_job.rb` (read/verify only unless needed for minimal compatibility)
- `test/ai/unit/tools/conversations/ask_advisor_tool_test.rb`
- `test/jobs/generate_advisor_response_job_test.rb` (only if needed for explicit ask-advisor regression coverage)
- Optional integration coverage target if needed for stability: `test/services/conversation_lifecycle_test.rb` (only if existing patterns require it)

## Scope assumptions
- Existing message rendering supports `role: system` + `status: pending` placeholders (already used in lifecycle paths).
- `GenerateAdvisorResponseJob` contract remains: process only pending messages; no change to that contract unless strictly necessary.
- Sender attribution should remain the initiating actor (`context[:user]` or `context[:advisor]`) while role reflects system/tool-generated message semantics.

## Implementation tasks (Builder)
1. Update `AskAdvisorTool#create_mention_message` in `app/libs/ai/tools/conversations/ask_advisor_tool.rb` to persist ask-advisor-created messages with processing-compatible state:
   - use non-user role for tool/system-generated message persistence,
   - use `status: "pending"` so enqueued job runs,
   - keep sender as initiator (`context[:user]` or `context[:advisor]`) unless validation requires a different existing convention.
2. Confirm enqueue payload remains unchanged (`advisor_id`, `conversation_id`, `message_id`) and still targets `GenerateAdvisorResponseJob.perform_later`.
3. Update/extend unit tests in `test/ai/unit/tools/conversations/ask_advisor_tool_test.rb`:
   - assert created message is not role `user`,
   - assert created message is `pending`,
   - assert sender attribution remains expected,
   - assert job enqueue is still triggered.
4. Add regression coverage for skip condition alignment:
   - ensure ask-advisor-created message shape satisfies job precondition (`pending?`),
   - verify no regression where ask-advisor jobs are skipped due to status mismatch.
5. Run targeted tests first, then broader relevant tests, and keep changes minimal if failures are unrelated.

## Verification
- Targeted unit tests:
  - `bin/rails test test/ai/unit/tools/conversations/ask_advisor_tool_test.rb`
- Targeted job tests:
  - `bin/rails test test/jobs/generate_advisor_response_job_test.rb`
- Optional focused integration check (only if touched):
  - `bin/rails test test/services/conversation_lifecycle_test.rb`
- Acceptance checks to confirm in test assertions:
  - No tool/system message in ask_advisor path is persisted as role `user`.
  - ask_advisor-enqueued jobs process pending messages (not skipped for `status != pending`).
  - No observable UI behavior change beyond corrected attribution/flow.

## Risks
- Existing tests may implicitly rely on incorrect role/state; updates must be limited to ask_advisor semantics.
- If any UI partial assumes ask_advisor message role is `user`, corrected role may reveal latent display assumptions.
- Over-correcting sender attribution could affect downstream logic; keep sender convention unchanged unless test evidence requires adjustment.

## Rollback notes
- Revert changes to `ask_advisor_tool` and associated tests.
- If deployed and rollback required, redeploy previous revision; no data migration rollback required because this is fix-forward only.

## Doc impact
- doc impact: none (behavior correction within existing flow; no user-facing feature/process change beyond bug fix semantics).

## Memory impact
- memory impact: none (no new durable repo convention discovered beyond existing documented tool/job pattern).

## Approval gate
- This plan is implementation-ready for Builder once explicitly approved.
