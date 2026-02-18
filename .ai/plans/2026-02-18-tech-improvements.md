# Plan: Technical Improvements - dotenv-rails + SimpleCov

**Date**: 2026-02-18  
**Goals**:
1. Move dotenv-rails to development/test only
2. Add simplecov and achieve 95%+ test coverage

---

## Current State Assessment

**Gemfile**:
- `dotenv-rails` currently in global scope (line 47)
- No test coverage tool installed
- ~330 tests passing across 34 test files

**Test Structure**:
- Models: 10 files (account, advisor, conversation, council, council_advisor, llm_model, message, provider, space, usage_record, user)
- Controllers: 14 files (all major controllers covered)
- Integration: 3 files (ai_response_flow, conversation_flow, rules_of_engagement_flow)
- Jobs: 1 file (generate_advisor_response_job)
- Services: 3 files (ai_client, scribe_coordinator, spaces/creation_service)
- System: 2 files (authentication, spaces)
- Mailers: 1 file (user_mailer)

**ENV Usage**:
- `APP_HOST` used in test/development for host configuration
- `RAILS_LOG_LEVEL` used in production with `ENV.fetch` default
- `CI` env var used in test.rb for eager_load
- Rails credentials used for encrypted secrets (not ENV files)

---

## Goal 1: Move dotenv-rails to Development/Test Only

### Goal
Prevent dotenv-rails from loading in production; use actual system ENV vars instead.

### Non-goals
- No changes to how ENV vars work in development/test
- No changes to application code that uses ENV
- No migration of secrets to Rails credentials (already using credentials pattern)

### Scope + Assumptions
- Production will use systemd, docker, or kamal secrets for env vars
- `.env` files are gitignored and never deployed
- Rails credentials (via `bin/rails credentials:edit`) handle encrypted secrets

---

## Goal 2: Add SimpleCov and Achieve 95%+ Coverage

### Goal
Install simplecov, configure it for Rails, run tests, identify coverage gaps, and add missing tests to reach 95%+ line coverage.

### Non-goals
- No changes to test framework (staying with Minitest)
- No branch coverage requirement initially (lines only)
- No integration with CI/coverage reporting services yet

### Scope + Assumptions
- Current ~330 tests provide baseline coverage
- Services/jobs likely have lower coverage than models/controllers
- 95% is achievable without major refactoring

---

## Implementation Steps

### Step 1: Move dotenv-rails to development/test group

**File**: `Gemfile`

1. Remove from global scope (line 47):
```ruby
# Remove these lines:
# Load environment variables from .env files
gem "dotenv-rails"
```

2. Add to `group :development, :test` block (around line 53-65):
```ruby
group :development, :test do
  # ... existing gems ...
  
  # Load environment variables from .env files (dev/test only)
  gem "dotenv-rails"
end
```

3. Run bundle install:
```bash
bundle install
```

**Verification**:
- [ ] `Gemfile.lock` shows dotenv-rails only in development/test groups
- [ ] `bundle exec rails runner "puts ENV['RAILS_ENV']"` works in production mode
- [ ] `.env` files are NOT loaded when `RAILS_ENV=production`

---

### Step 2: Add simplecov gem

**File**: `Gemfile`

Add to `group :test` block (around line 78-83):
```ruby
group :test do
  # ... existing gems ...
  
  # Code coverage analysis
  gem "simplecov", require: false
end
```

Run bundle install:
```bash
bundle install
```

---

### Step 3: Configure simplecov

**File**: `test/test_helper.rb`

Add at the very top (before all other requires):
```ruby
require "simplecov"
SimpleCov.start "rails" do
  # Exclude test/config directories
  add_filter "/test/"
  add_filter "/config/"
  
  # Group related files for better reporting
  add_group "Models", "app/models"
  add_group "Controllers", "app/controllers"
  add_group "Services", "app/services"
  add_group "Jobs", "app/jobs"
  add_group "Mailers", "app/mailers"
  add_group "Helpers", "app/helpers"
end
```

**Verification**:
- [ ] SimpleCov loads without errors: `bin/rails test test/models/user_test.rb`
- [ ] Coverage directory created: `ls coverage/`
- [ ] HTML report viewable: `coverage/index.html`

---

### Step 4: Run full test suite and analyze coverage

**Command**:
```bash
rm -rf coverage/
bin/rails test
```

**Check coverage output**:
```bash
cat coverage/coverage.json | jq '.metrics'  # if json available
# Or open coverage/index.html in browser
```

**Verification**:
- [ ] All ~330 tests pass
- [ ] Coverage report generated
- [ ] Document current coverage percentage

---

### Step 5: Identify coverage gaps

**Common gaps to check**:

1. **Services** (`app/services/`):
   - `ai_client.rb` - check error handling paths
   - `scribe_coordinator.rb` - check edge cases
   - `spaces/creation_service.rb` - check validation failures

2. **Jobs** (`app/jobs/`):
   - `generate_advisor_response_job.rb` - check error handling, retries

3. **Models** - check uncovered methods:
   - Look for scopes not tested
   - Check custom validation methods
   - Check callback methods

4. **Controllers** - check edge cases:
   - Error paths (422, 500 responses)
   - Unauthorized access attempts
   - Parameter validation failures

**Analysis steps**:
```bash
# View uncovered lines
grep -r "0 hits" coverage/*.html 2>/dev/null || echo "Check coverage/index.html manually"

# List files with < 100% coverage
cat coverage/coverage.json 2>/dev/null | jq '.files[] | select(.coverage < 100) | {file: .filename, coverage: .coverage}'
```

---

### Step 6: Add missing tests to reach 95%+

**Priority order** (lowest coverage first):

1. **Services tests**:
   - `test/services/ai_client_test.rb` - add error handling tests
   - `test/services/scribe_coordinator_test.rb` - add edge case tests
   - `test/services/spaces_creation_service_test.rb` - add validation failure tests

2. **Job tests**:
   - `test/jobs/generate_advisor_response_job_test.rb` - add retry/error tests

3. **Controller edge cases**:
   - Add tests for invalid params (422 responses)
   - Add tests for not-found scenarios
   - Add tests for authorization edge cases

**Example test additions**:

```ruby
# test/services/ai_client_test.rb - add error handling
test "handles API timeout gracefully" do
  stub_request(:post, /openai/).to_timeout
  assert_raises AIClient::Error do
    @client.chat(messages: [{role: "user", content: "hi"}])
  end
end

# test/jobs/generate_advisor_response_job_test.rb - add retry logic
test "retries on transient API errors" do
  advisor = advisors(:one)
  message = messages(:one)
  
  # Stub to simulate failure then success
  call_count = 0
  GenerateAdvisorResponseJob.any_instance.stubs(:call_api).returns do
    call_count += 1
    call_count == 1 ? raise(AIClient::Error, "timeout") : OpenStruct.new(content: "response")
  end
  
  # Should complete on retry
  assert_nothing_raised { perform_enqueued_jobs }
end
```

**Verification**:
- [ ] Coverage report shows 95%+ overall
- [ ] No file below 90% coverage (unless documented)
- [ ] All new tests pass

---

### Step 7: Update documentation

**File**: `.ai/MEMORY.md`

Add to "Commands" section:
```markdown
- Coverage: `bin/rails test` then `open coverage/index.html`
```

Add to "Gems" section:
```markdown
- `simplecov` - Code coverage analysis (test group only)
```

Add new section:
```markdown
## Test Coverage
- Current: 95%+ (TARGET after this plan)
- Tool: simplecov
- Report: `coverage/index.html` after running tests
- Excluded: test/, config/
```

Update "Configuration Pattern" section to document ENV handling:
```markdown
- dotenv-rails: dev/test only (production uses system ENV vars)
- Required ENV vars for production: APP_HOST (optional), RAILS_LOG_LEVEL (optional, defaults to info)
```

---

## Verification Checklist

### Goal 1 Verification:
- [ ] `bundle exec rails runner 'puts ENV.keys.count'` in production mode shows no .env loading
- [ ] `Gemfile.lock` shows dotenv-rails only under `development` and `test` groups
- [ ] Production container/systemd service can start with ENV vars from system

### Goal 2 Verification:
- [ ] `bin/rails test` runs without simplecov errors
- [ ] `coverage/index.html` generated and viewable
- [ ] Overall coverage >= 95%
- [ ] All files >= 90% coverage (or explicitly documented why not)
- [ ] `.ai/MEMORY.md` updated with coverage info

### General Verification:
- [ ] All ~330 existing tests still pass
- [ ] No regressions in CI (if applicable)
- [ ] Can boot Rails console in production mode locally: `RAILS_ENV=production bundle exec rails console`

---

## Doc Impact

- **Updated**: `.ai/MEMORY.md` (add simplecov info, coverage target, ENV handling notes)
- **Deferred**: `.ai/docs/patterns/testing.md` (create later if needed)

---

## Rollback

If dotenv-rails move causes issues:
1. Revert Gemfile changes: move `gem "dotenv-rails"` back to global scope
2. Run `bundle install`
3. Verify `.env` loads in production: `bundle exec rails runner "puts ENV['KEY_FROM_DOTENV']"`

If simplecov causes issues:
1. Remove simplecov from Gemfile
2. Revert test/test_helper.rb changes
3. Delete coverage directory: `rm -rf coverage/`

---

## Unknowns / Risks

1. **Production ENV var discovery**: Need to verify all required ENV vars are documented. Check kamal deploy config or systemd unit files.
2. **SimpleCov parallel test compatibility**: Parallel testing with multiple workers may need special configuration.
3. **Coverage target feasibility**: 95% may require significant test additions if services/jobs are largely uncovered.

---

## Approval Request

Approve this plan? Once approved, implementation can proceed.
