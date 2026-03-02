# Plan: temporarily disable ask_advisor across all advisors (hard remove)

Date: 2026-03-02
Type: bug
Supersedes: `.ai/plans/2026-03-02-04-ask-advisor-attribution-and-pending-fix.md`

## Intake summary (confirmed)
- Change type: bug fix
- Mode: hard remove `ask_advisor` from all advisor tool lists
- Fallback requirement: if `ask_advisor` is still called, return graceful unavailable error with no side effects

## Goal
- Temporarily disable `ask_advisor` safely by removing exposure everywhere advisors get tools, while preserving system stability if stale or direct calls occur.

## Non-goals
- No redesign of tool architecture or dynamic feature-flag system.
- No changes to other conversation tools or message lifecycle behavior beyond this specific tool disablement.
- No backfill/migration for historical messages.

## Scope + assumptions
- Scope is limited to tool exposure/registration, defensive tool behavior, and regression tests.
- Existing tool dispatch and adapter behavior should remain unchanged for all non-`ask_advisor` tools.
- Temporary disablement is code-based (not runtime toggle) for minimal risk and predictable behavior.

## Evidence snapshot
- `ask_advisor` is currently exposed in advisor tool assembly: `app/libs/ai/content_generator.rb` (`advisor_tools`).
- `ask_advisor` implementation currently creates conversation messages and enqueues `GenerateAdvisorResponseJob`: `app/libs/ai/tools/conversations/ask_advisor_tool.rb`.
- Current tests explicitly assert tool exposure for regular advisors and scribe: `test/ai/unit/content_generator_test.rb`.
- Dedicated unit tests exist for tool behavior: `test/ai/unit/tools/conversations/ask_advisor_tool_test.rb`.

## Exact file targets (likely)
- Tool registry/config + exposure:
  - `app/libs/ai/content_generator.rb`
- Tool fallback behavior (defensive no-op with graceful error):
  - `app/libs/ai/tools/conversations/ask_advisor_tool.rb`
- Regression tests for exposure and unaffected tools:
  - `test/ai/unit/content_generator_test.rb`
- Regression tests for disabled-tool fallback/no-side-effects contract:
  - `test/ai/unit/tools/conversations/ask_advisor_tool_test.rb`
- Optional targeted job-safety assertion (only if needed by existing patterns):
  - `test/jobs/generate_advisor_response_job_test.rb`

## Steps
1. Remove `AI::Tools::Conversations::AskAdvisorTool` from advisor tool assembly in `app/libs/ai/content_generator.rb` for both regular advisors and scribe paths (via shared read-only list), and adjust any tool-count expectations.
2. Convert `AskAdvisorTool#execute` in `app/libs/ai/tools/conversations/ask_advisor_tool.rb` to immediate graceful-unavailable behavior:
   - return structured failure (e.g., `success: false`, unavailable message/code),
   - do not create messages,
   - do not enqueue jobs,
   - keep interface shape stable to avoid upstream exceptions.
3. Update `test/ai/unit/content_generator_test.rb`:
   - assert `AskAdvisorTool` is absent from advisor tool classes,
   - assert non-`ask_advisor` tools remain present for regular advisors and scribe,
   - update tool-count assertions to new expected totals.
4. Update `test/ai/unit/tools/conversations/ask_advisor_tool_test.rb`:
   - assert disabled execution returns graceful unavailable error payload,
   - assert `Message.count` unchanged,
   - assert no `GenerateAdvisorResponseJob` enqueue side effect,
   - keep/adjust metadata assertions (`name`, schema) only as needed to reflect temporary disablement contract.
5. Run targeted verification commands and confirm acceptance criteria before any broader test sweep.

## Acceptance criteria
1. `ask_advisor` is not available to any advisor/tool list.
2. Calls to `ask_advisor` return graceful unavailable error and create no messages/jobs.
3. Existing non-`ask_advisor` tools are unaffected.
4. Regression tests are updated and passing for changed behavior.

## Verification
- Targeted tool exposure tests:
  - `bin/rails test test/ai/unit/content_generator_test.rb`
- Targeted disabled-tool behavior tests:
  - `bin/rails test test/ai/unit/tools/conversations/ask_advisor_tool_test.rb`
- Optional targeted job test (if touched):
  - `bin/rails test test/jobs/generate_advisor_response_job_test.rb`

## Risks
- Tool-count assertions may fail in multiple places after removal; updates must stay limited to `ask_advisor` expectations.
- Some prompts/responses from prior runs may reference `ask_advisor`; defensive fallback prevents side effects if called anyway.
- Over-scoping into unrelated tool ordering/selection logic should be avoided.

## Rollback
- Revert changes in `app/libs/ai/content_generator.rb`, `app/libs/ai/tools/conversations/ask_advisor_tool.rb`, and associated tests.

## Doc impact
- doc impact: none (temporary internal tool availability change; no new user workflow documented yet).

## Memory impact
- memory impact: none (temporary operational change, not a durable repository convention).

## Approval gate
- Approve this plan?
