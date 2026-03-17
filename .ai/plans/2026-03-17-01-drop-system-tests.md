# Plan: Drop Rails System Tests and Setup

## Date
2026-03-17

## Workflow
change (type=refactor)

## Scope (approved)
- Remove all Rails system tests.
- Remove system-test setup and CI/docs references.
- Keep `mocha` dependency as requested.

## Out of Scope
- Any non-system test refactors.
- Test architecture changes beyond removing system-test paths.

## Implementation Steps
1. Remove system test files:
   - `test/system/authentication_test.rb`
   - `test/system/spaces_test.rb`
   - `test/application_system_test_case.rb`
2. Remove Capybara/Cuprite configuration from `test/test_helper.rb`.
3. Update `Gemfile` to remove `capybara` and `cuprite` from `:test` group.
4. Run `bundle install` to refresh `Gemfile.lock` and remove now-unused transitive gems.
5. Remove `system-test` job from `.github/workflows/ci.yml`.
6. Remove stale system-test references in:
   - `README.md`
   - `.ai/docs/patterns/testing.md`
   - `.ai/MEMORY.md`
7. Validate with focused checks:
   - `bundle exec ruby -c test/test_helper.rb`
   - `bundle exec rails test`

## Risks and Mitigations
- Risk: hidden reliance on Capybara config in non-system tests.
  - Mitigation: run full `rails test` suite and fix only directly related breakages.
- Risk: lockfile drift from dependency removal.
  - Mitigation: regenerate lockfile via bundler and verify clean install.

## Acceptance Criteria
- No files remain under `test/system`.
- `test/application_system_test_case.rb` is removed.
- `Gemfile` no longer includes `capybara`/`cuprite`.
- CI workflow has no `system-test` job.
- Docs no longer claim system-test coverage.
- Test suite passes (or failures are reported with context).
