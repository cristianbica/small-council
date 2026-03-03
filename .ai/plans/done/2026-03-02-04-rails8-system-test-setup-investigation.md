# Investigation Report: Rails 8-era system test setup for remaining failures

## 1) Intent
- Question to answer: What does latest Rails recommend for system tests, what CI/local driver setups are most stable, and how should this repo address remaining failing system tests (notably browser session startup failures) without changing product code in this step?
- Success criteria:
  - Capture Rails/Selenium/Capybara authoritative guidance.
  - Map that guidance to current repo configuration.
  - Provide prioritized, minimal next-step scope for a follow-on `change` workflow.

## 2) Scope + constraints
- In-scope:
  - Rails 8-era defaults and guidance for system tests.
  - Stable local and CI driver patterns.
  - `SessionNotCreatedError` causes and mitigations.
  - Repo-specific recommendations for `/root/p/small-council`.
- Out-of-scope:
  - Any product or test code changes.
  - Executing tests/commands in this investigation.
- Read-only default acknowledged: yes.
- Instrumentation/spikes allowed: no.
- Timebox: one focused investigation pass.

## 3) Evidence collected

### Authoritative external sources
- Rails Guides: `Testing Rails Applications` (System Testing sections)
  - https://guides.rubyonrails.org/testing.html
- Rails API: `ActionDispatch::SystemTestCase`
  - https://api.rubyonrails.org/classes/ActionDispatch/SystemTestCase.html
- Rails source/docs snippets (generator + guides + defaults)
  - `guides/source/testing.md` (system test generation/defaults)
  - `actionpack/lib/action_dispatch/system_test_case.rb` (defaults and API)
  - `guides/source/7_2_release_notes.md` (headless Chrome default for new apps)
- Selenium docs:
  - Common errors / `SessionNotCreatedException`
    - https://www.selenium.dev/documentation/webdriver/troubleshooting/errors/#sessionnotcreatedexception
  - Selenium Manager
    - https://www.selenium.dev/documentation/selenium_manager/
- Capybara docs:
  - README sections for remote servers / waiting / driver behavior
    - https://github.com/teamcapybara/capybara

### Repo files inspected
- `test/application_system_test_case.rb`
- `test/test_helper.rb`
- `test/system/authentication_test.rb`
- `test/system/spaces_test.rb`
- `.github/workflows/ci.yml`
- `config/ci.rb`
- `Gemfile`
- Existing prior plan context: `.ai/plans/2026-03-02-03-fix-failing-tests.md`

## 4) Findings

### A. What latest Rails recommends by default for system tests
1. Core default runtime
   - `ActionDispatch::SystemTestCase` defaults to Selenium + Chrome + `1400x1400` screen size.
   - Rails docs and API both state this default.
2. Practical Rails app default pattern in recent generators/docs
   - Rails examples and generated test fixtures commonly use:
     - `driven_by :selenium, using: :headless_chrome`
   - Rails 7.2 release notes explicitly note headless Chrome as default for new apps; Rails 8-era docs continue documenting headless Chrome patterns.
3. Scope recommendation
   - Rails Guides now explicitly suggest system tests for critical paths (not every flow), because they are slower and more brittle than lower-level tests.
4. Execution model
   - `bin/rails test` does not include system tests by default.
   - Run `bin/rails test:system` separately, or `bin/rails test:all`.

### B. Stable CI/local driver configuration patterns
1. Local baseline (single-machine)
   - Keep `driven_by :selenium, using: :headless_chrome` in `ApplicationSystemTestCase`.
   - Keep configuration centralized in `test/application_system_test_case.rb`.
2. Remote browser/grid/container baseline
   - Rails Guides recommend env-gated remote Selenium URL pattern:
     - local: chrome/headless_chrome
     - remote: `{ browser: :remote, url: ... }`
   - For remote browser usage, add Capybara host wiring (`server_host`, `app_host`) when app/browser are in different containers/hosts.
3. CI baseline
   - Separate system tests into their own CI job (this repo already does).
   - Preserve failed screenshots as artifacts (this repo already does).
   - Ensure browser runtime + shared libraries are installed/available in runner image (or use remote selenium container).
4. Driver binary management
   - Selenium Manager is official and shipped with Selenium (since Selenium 4.6); it auto-resolves driver/browser when missing.
   - This reduces manual `chromedriver` pinning, but CI still needs compatible browser runtime and network access (for manager fetches).

### C. Common causes of Chrome SessionNotCreatedError and mitigations
From Selenium docs and Rails/Capybara operational patterns:

Common causes
1. Browser/driver version incompatibility.
2. Missing/inaccessible driver binary or permissions.
3. Browser not present or missing runtime libs in Linux containers/CI.
4. Environment/network restrictions preventing Selenium Manager fetches.
5. Incorrect remote/local config mismatch (trying local launch in environment expecting remote grid).

Mitigations
1. Prefer Selenium Manager defaults; avoid mixed manual old driver binaries.
2. Ensure Chrome/Chromium runtime and required shared libs are installed in CI image.
3. If using remote Selenium, explicitly set remote URL env var and Capybara host/app host wiring.
4. Capture Selenium debug logs for failing sessions and record browser/driver versions in CI output.
5. For constrained networks, preinstall browser/driver or configure Selenium Manager proxy/cache settings.

### D. Repo-specific map

Current strengths
- `test/application_system_test_case.rb` already uses headless Chrome and supports remote selenium via env var.
- CI already splits `test` and `system-test` jobs and uploads screenshots on failure.
- Gem setup includes `capybara` + `selenium-webdriver` in test group.

Current mismatches / likely risk points
1. Env var naming drift from Rails docs
   - Repo uses `SELENIUM_URL`; Rails guide examples use `SELENIUM_REMOTE_URL`.
   - Not inherently broken, but it increases integration ambiguity.
2. CI system-test job installs only `libpq-dev` explicitly.
   - Browser availability is implicitly inherited from runner image; if image/browser changes, startup can fail as `SessionNotCreatedError`.
3. Existing known context already flags Selenium startup failures in this repo’s test planning artifacts.

Confidence: high on framework-level recommendations; medium-high on repo-specific root-cause likelihood (without re-running failing tests/logs in this step).

## 5) Prioritized recommendations (top 5)
1. **Standardize remote env contract to Rails naming (`SELENIUM_REMOTE_URL`)**
   - Keep backward compatibility (`SELENIUM_URL` alias) only during migration window.
   - Why first: removes config ambiguity between docs, local runs, and CI/container setups.

2. **Make browser runtime explicit in system-test CI job**
   - Either:
     - explicit install/verify of Chrome/Chromium + required libs in the job, or
     - explicit remote Selenium service/container for system tests.
   - Why first: most direct hedge against `SessionNotCreatedError` drift from runner image changes.

3. **Add deterministic local/CI mode switch in `ApplicationSystemTestCase`**
   - One canonical branch for local headless, one for remote selenium, with corresponding Capybara host wiring for remote mode.
   - Why: aligns exactly with Rails guide remote-server pattern and avoids mixed-mode failures.

4. **Add startup diagnostics for system-test failures**
   - On system-test boot failure, log browser version, Selenium version, selected driver mode, and remote URL presence.
   - Why: turns intermittent SessionNotCreated failures into actionable data.

5. **Constrain system tests to critical user paths and keep selector assertions resilient**
   - Current count is small (good); keep this as policy for future additions.
   - Why: reduces flakiness and CI cost while preserving end-to-end confidence.

## 6) Recommended command snippets (do not execute in this report)
- Run only system tests:
  - `bin/rails test:system`
- Run one system file:
  - `bin/rails test test/system/authentication_test.rb`
- Run with remote selenium endpoint:
  - `SELENIUM_REMOTE_URL=http://localhost:4444/wd/hub bin/rails test:system`
- Capture fuller failure traces:
  - `bin/rails test:system -b`

## 7) Handoff
- Next workflow: `change` (bug)
- Minimal next-step scope:
  1. Update only test/CI configuration surface (no product behavior changes).
  2. Normalize selenium env var contract and remote/local mode branching in `test/application_system_test_case.rb`.
  3. Harden `.github/workflows/ci.yml` `system-test` job browser prerequisites and diagnostics.
  4. Validate by running only `test/system/authentication_test.rb` and `test/system/spaces_test.rb` in CI-equivalent mode.

Verification plan for follow-on change
- `bin/rails test test/system/authentication_test.rb`
- `bin/rails test test/system/spaces_test.rb`
- `bin/rails test:system`

## 8) Open questions
1. Do you want to keep local system tests fully local-browser, or standardize on remote Selenium for both local and CI?
2. In CI, do you prefer runner-native Chrome or explicit Selenium container service for stronger reproducibility?

## 9) Doc impact
- updated (this report file only)

## 10) Memory impact
- none (no new durable repo convention verified beyond current curated memory)
