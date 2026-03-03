# Plan: Fix failing test suite with minimal bug-fix scope

## Goal
Restore test suite stability by fixing current regressions with the smallest product-code changes needed, prioritizing shared root causes first.

## Non-goals
- No feature expansion beyond what failing tests require.
- No broad UI redesign or refactor unrelated to failures.
- No speculative performance/security hardening outside failing paths.

## Context and evidence
User reported latest run: **1433 runs, 35 failures, 6 errors**.

Fresh local evidence from Planner run:
- `runTests` summary: **1333 passed, 42 failed**.
- Dominant failures are consistent with recent advisor-name canonicalization (`name` now normalized to lowercase handle format).

Observed failure clusters:
1. **Advisor display-name vs canonical-handle regression (largest cluster)**
   - Many tests expect human-readable advisor names (`"Test Advisor"`, `"Scribe"`) but app now stores/returns canonical handles (`"test-advisor"`, `"scribe"`).
   - Affects models, controllers, context builders, tools, and integration flows.
   - Example loci: `app/models/advisor.rb`, `app/services/conversation_lifecycle.rb`, `app/services/commands/invite_command.rb`.

2. **Account/space authorization response semantics mismatch**
   - Tests expect `404` for cross-account access; controllers currently rescue and redirect (`302`) to space councils.
   - Example loci: `app/controllers/conversations_controller.rb`, `app/controllers/messages_controller.rb`.

3. **System test harness regressions**
   - `NoMethodError: sign_in_as` in system tests (`ApplicationSystemTestCase` does not expose integration helper).
   - Selenium/Chrome session boot errors in environment (`SessionNotCreatedError`).

4. **AI-specific unit regressions (small cluster)**
   - Cache behavior test failing due `fetch_from_cache` short-circuit returning block value.
   - ModelInteraction event-handler test failing (chat instrumentation path not recording in test scenario).

## Scope assumptions (needs approval)
- Primary fix direction is to restore previously expected display-name behavior for advisor-facing text while preserving mention parsing correctness.
- System-test Selenium startup issues are treated as environment gate unless reproducible as app misconfiguration in-repo.

## Execution phases (for Builder)

1. **Reproduce and baseline by cluster (targeted-first)**
   - Run focused failing subsets first (advisor/model/controller/integration/system/ai) and capture per-cluster baseline counts.
   - Keep a short running checklist of files and assertions fixed per cluster.

2. **Fix cluster A: advisor naming contract regressions**
   - Decide and enforce one consistent contract:
     - Either restore display names in `Advisor#name` usage surfaces, or
     - Keep canonical handles but reintroduce display semantics where UI/context/tests require them.
   - Update mention/invite matching paths to remain deterministic with chosen contract.
   - Resolve duplicate `Scribe` creation failures in jobs by aligning uniqueness + fixture/setup expectations with contract.

3. **Fix cluster B: access-control response semantics**
   - Align controller behavior with security test expectations for cross-account/cross-space access (prefer explicit `404` for inaccessible records).
   - Keep user-facing redirect behavior only where tests/specs explicitly require it for same-account UX paths.

4. **Fix cluster C: system test harness**
   - Add/restore shared auth helper availability for system tests (`sign_in_as`) in `ApplicationSystemTestCase` (or shared module include).
   - Gate Selenium failures:
     - If environment-only (no Chrome in CI/local), document and isolate.
     - If app config issue, apply minimal in-repo fix.

5. **Fix cluster D: AI unit regressions**
   - Re-enable intended cache-path behavior in `ContentGenerator#fetch_from_cache` (or adjust test only if behavior was intentionally changed and documented).
   - Make event-handler recording path deterministic for `AI::Client` test scenario.

6. **Verification sweep**
   - Re-run the targeted subsets first until green.
   - Then run broader suite (`bin/rails test`) to confirm no regressions and collect final counts.

## Suggested targeted verification order
1. `bin/rails test test/models/advisor_comprehensive_test.rb test/models/space_test.rb test/models/memory_test.rb test/models/memory_version_test.rb`
2. `bin/rails test test/controllers/advisors_controller_test.rb test/controllers/advisors_controller_comprehensive_test.rb test/controllers/conversations_controller_test.rb test/controllers/messages_controller_test.rb test/controllers/security_controller_test.rb`
3. `bin/rails test test/integration/conversation_flow_test.rb test/integration/rules_of_engagement_flow_test.rb test/integration/complete_conversation_flows_test.rb`
4. `bin/rails test test/jobs/generate_advisor_response_job_test.rb`
5. `bin/rails test test/ai/unit/client_test.rb test/ai/unit/content_generator_test.rb test/ai/unit/tools/conversations/ask_advisor_tool_test.rb`
6. `bin/rails test test/system/authentication_test.rb test/system/spaces_test.rb` (if browser env available)
7. `bin/rails test`

## Acceptance criteria
- All previously failing non-system tests in the identified clusters are green.
- Cross-account security expectations are consistent and covered by controller tests.
- Advisor naming behavior is internally consistent across model, controller, integration, and AI context/tool tests.
- System test status is either green or explicitly documented as environment-blocked with evidence.
- Full suite run shows a materially reduced failure count, with no new unrelated failures introduced.

## Risks and guardrails
- **Risk:** Mixing display-name and handle semantics can create hidden edge cases.
  - **Guardrail:** Pick one documented contract and apply consistently at model boundary.
- **Risk:** Changing 302/404 behavior may impact UX flows.
  - **Guardrail:** Separate same-account UX redirects from cross-account authorization failures.
- **Risk:** System test failures may mask real app issues.
  - **Guardrail:** Validate helper wiring separately from browser runtime prerequisites.

## Deliverables
- Product/test code changes limited to failing clusters above.
- Short implementation report with:
  - exact tests run,
  - before/after fail counts,
  - any unresolved blockers.

## doc impact
- **deferred** (update relevant docs after implementation outcome is known)

## memory impact
- **placeholder** (add durable command/convention only if newly verified during Builder run)

## Blocking unknowns / decisions for approval
1. Should we **restore display-name expectations** (e.g., `"Scribe"`, `"Test Advisor"`) as canonical behavior, or keep strict canonical handles and instead update broad test expectations accordingly?
2. For cross-account record access in controllers, should final product behavior be strict `404` (security-first) where tests currently assert it?

---
Approve this plan?
