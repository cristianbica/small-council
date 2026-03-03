# Plan: Switch Rails system tests from Selenium to Cuprite

## Goal
Replace Selenium-based system test driver setup with Cuprite while keeping product behavior unchanged and preserving reliable local + CI system test execution.

## Non-goals
- No application feature or UX changes.
- No changes to non-system test behavior.
- No broad CI refactor outside what is necessary for system test browser wiring.

## Intent and constraints (confirmed)
- Intent: "switch to cuprite".
- Existing local env: `.env.test` already contains `CHROME_URL="http://127.0.0.1:9222"` and is reported as working.
- Scope must remain test infrastructure only.

## Evidence snapshot
- Current driver setup is Selenium in `test/application_system_test_case.rb` with `SELENIUM_URL` remote toggle.
- `Gemfile` test group includes `selenium-webdriver` and `capybara`, but not Cuprite.
- CI system tests run in `.github/workflows/ci.yml` under `system-test` without explicit browser service/config.
- Current system test files are `test/system/authentication_test.rb` and `test/system/spaces_test.rb`.

## Likely files to touch (exact)
1. `Gemfile`
2. `Gemfile.lock`
3. `test/application_system_test_case.rb`
4. `test/test_helper.rb` (only if shared support loading is needed)
5. `test/support/cuprite.rb` (new, if driver registration is extracted)
6. `.github/workflows/ci.yml` (if CI needs explicit Chrome remote debugging endpoint)
7. `.env.test` (no committed secret changes expected; document-only usage contract)

## Implementation plan (bug-fix, minimal)
1. **Add Cuprite dependency and remove Selenium coupling for system tests**
   - Add `cuprite` to the test group in `Gemfile`.
   - Remove `selenium-webdriver` only if no non-system tests still require it.
   - Run bundler to update `Gemfile.lock`.

2. **Introduce a single Cuprite driver contract for system tests**
   - Update `test/application_system_test_case.rb` to `driven_by :cuprite`.
   - Register/configure a Cuprite driver once (inline or via `test/support/cuprite.rb`) with sane defaults:
     - headless true
     - window size equivalent to current `1400x1400`
     - timeout tuned for current suite (minimal change)

3. **Handle `CHROME_URL` with explicit fallback behavior**
   - If `ENV["CHROME_URL"]` is present: connect Cuprite/Ferrum to that remote Chrome endpoint.
   - If absent: start local headless Chrome via Cuprite defaults (no remote dependency).
   - Keep behavior deterministic by centralizing this branch in one place (system test case or support file).
   - Optional short compatibility bridge (timeboxed): if `SELENIUM_URL` is present and `CHROME_URL` absent, map to new path temporarily; remove after migration stabilization.

4. **Align CI system-test job only as needed for Cuprite**
   - If relying on remote Chrome in CI, ensure `.github/workflows/ci.yml` provides an endpoint consumable as `CHROME_URL`.
   - If relying on local browser process in CI, ensure required browser/runtime deps are explicitly available.
   - Keep CI changes constrained to `system-test` job; avoid touching lint/unit jobs.

5. **Remove Selenium-specific assumptions from system test infrastructure**
   - Delete obsolete Selenium-only options/branches in `test/application_system_test_case.rb`.
   - Keep helper methods (e.g., sign-in helper) intact.

## Verification plan (targeted first)
1. Confirm dependency/install state after gem updates (`bundle install` / `bundle check`).
2. Run known failing/critical system tests first:
   - `bin/rails test test/system/authentication_test.rb`
   - `bin/rails test test/system/spaces_test.rb`
3. Run broader system suite:
   - `bin/rails test:system`
4. (If CI changed) validate CI-equivalent environment path for `CHROME_URL` and screenshot artifact behavior on failure.

## Acceptance criteria
- System tests run via Cuprite (no Selenium driver path in system test setup).
- `CHROME_URL` path works when provided.
- Local fallback works without `CHROME_URL`.
- `test/system/authentication_test.rb` and `test/system/spaces_test.rb` pass (or produce only pre-existing unrelated failures).
- `bin/rails test:system` completes without Selenium session boot errors.

## Risks and mitigations
- **Risk:** CI lacks a compatible Chrome runtime/endpoint for Cuprite.
  - **Mitigation:** Keep CI changes narrowly scoped and verify `CHROME_URL` contract explicitly.
- **Risk:** Hidden Selenium dependency elsewhere in tests.
  - **Mitigation:** Remove Selenium gem only after confirming no remaining references.
- **Risk:** Remote endpoint format mismatch for `CHROME_URL`.
  - **Mitigation:** Document expected format (`http://host:9222`) and fail fast with clear error.

## Doc impact
- **updated**: add/adjust test setup notes (README or `.ai/docs/` testing docs) to describe Cuprite + `CHROME_URL` fallback contract.

## Memory impact
- If migration is verified, append one durable bullet to `.ai/MEMORY.md` with the confirmed system test command/environment convention.

---
Approve this plan?
