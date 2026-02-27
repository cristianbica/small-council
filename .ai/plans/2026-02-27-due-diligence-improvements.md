# Due Diligence Improvement Plan

**Date:** 2026-02-27
**Status:** DRAFT - Awaiting Approval
**Risk Level:** CRITICAL - Job losses possible if due diligence fails
**Estimated Duration:** 30 days (6 weeks)
**Target Completion:** 2026-04-10

---

## Executive Summary

This plan addresses 29 identified security, maintainability, and readability issues across the Small Council Rails application. The issues span from CRITICAL (SSL disabled, CSP disabled, API keys in URLs) to LOW (minor hygiene). Due diligence failure could result in significant valuation reduction or deal collapse.

### Key Metrics
- **CRITICAL Issues:** 3 (security)
- **HIGH Issues:** 8 (security + maintainability)
- **MEDIUM Issues:** 12 (maintainability + testing)
- **LOW Issues:** 6 (readability + hygiene)
- **Total Service Code:** 8,058 lines
- **Total Test Code:** ~2,500 lines (services only ~900 lines)
- **Test Coverage Gap:** ~65% of service code untested

---

## Risk Matrix

| Issue | Severity | Likelihood | Impact | Risk Score | Due Diligence Impact |
|-------|----------|------------|--------|------------|---------------------|
| SSL disabled in production | Critical | Certain | Severe | 10/10 | Dealbreaker - data exposure liability |
| CSP disabled | Critical | Certain | High | 9/10 | Dealbreaker - XSS vulnerability |
| API keys in URLs | Critical | Confirmed | High | 9/10 | Dealbreaker - credential exposure |
| Debug info exposed to all users | High | Confirmed | Medium | 7/10 | High - information disclosure |
| SQL injection vulnerability | High | Confirmed | High | 8/10 | High - data breach risk |
| No rate limiting | High | Certain | Medium | 6/10 | Medium - DDoS vulnerability |
| Session cookie security | High | Likely | Medium | 6/10 | Medium - session hijacking |
| Missing security headers | High | Certain | Low | 5/10 | Medium - defense in depth |
| God classes (AIClient 480 lines) | Medium | Confirmed | Medium | 5/10 | Medium - maintainability concern |
| Tool hierarchy duplication | Medium | Confirmed | Low | 4/10 | Low - code complexity |

---

## Phase 1: Critical Security Fixes (Days 1-3)

**Goal:** Fix issues that are absolute dealbreakers for due diligence
**Priority:** MUST complete before any other work
**Success Criteria:** All CRITICAL issues resolved and verified

### Day 1: SSL and CSP (Effort: 4 hours)

#### Task 1.1: Enable SSL in Production
**File:** `config/environments/production.rb` (line 31)
**Current:** `# config.force_ssl = true` (commented out)
**Required:** Uncomment and verify
**Risk if not fixed:** All data transmitted in plaintext; immediate dealbreaker
**Verification:**
```bash
# After deployment, verify HTTPS redirect
curl -I http://small-council.example.com
# Expect: 301 redirect to HTTPS
```

#### Task 1.2: Enable Content Security Policy
**File:** `config/initializers/content_security_policy.rb` (lines 7-29)
**Current:** All CSP configuration commented out
**Required:** Enable with strict defaults for production
**Implementation:**
```ruby
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data
    policy.object_src  :none
    policy.script_src  :self, :https
    policy.style_src   :self, :https
    policy.connect_src :self, :https
  end
end
```
**Risk if not fixed:** XSS attacks possible; content injection
**Verification:** Check response headers include `Content-Security-Policy`

#### Task 1.3: Filter API Keys from Logs
**File:** `config/initializers/filter_parameter_logging.rb` (line 7)
**Current:** Missing `api_key` from filter list
**Required:** Add `:api_key` to filter_parameters array
**Risk if not fixed:** API credentials exposed in log files
**Verification:** Check production logs don't contain plaintext API keys

### Day 2: API Key Handling (Effort: 6 hours)

#### Task 1.4: Remove API Keys from URL Parameters
**File:** `app/controllers/providers_controller.rb` (lines 70, 75)
**Current:** API keys passed as query parameters in redirect URLs
**Required:** Use encrypted session storage or form resubmission pattern
**Implementation Options:**
1. Encrypt and store in session (preferred)
2. Re-prompt user for API key on step 3
3. Use hidden form fields with POST redirects
**Risk if not fixed:** API keys visible in server logs, browser history, referrer headers
**Dependencies:** Task 1.3 must be complete
**Verification:**
- Complete wizard flow
- Check logs contain no API keys
- Check browser history contains no API keys

#### Task 1.5: Secure Session Cookies
**File:** Create `config/initializers/session_store.rb`
**Current:** Default Rails session configuration (likely insecure)
**Required:** Configure secure, httponly, same_site cookies
**Implementation:**
```ruby
Rails.application.config.session_store :cookie_store,
  key: '_small_council_session',
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax
```
**Risk if not fixed:** Session hijacking, CSRF attacks
**Verification:** Inspect Set-Cookie headers in production

### Day 3: Debug Info Exposure (Effort: 4 hours)

#### Task 1.6: Restrict Debug Information Access
**File:** `app/views/messages/_message.html.erb` (lines 84-118)
**Current:** Debug modal shown to all users for all advisor messages
**Required:** Restrict to admins/developers only
**Implementation:**
```erb
<% if is_advisor && message.prompt_text.present? && Current.user.admin? %>
  <!-- debug modal -->
<% end %>
```
**Alternative:** Add `debug_visible?` method to User model
**Risk if not fixed:** Information disclosure, prompt injection techniques exposed
**Verification:** Log in as regular user, verify no debug button visible

#### Task 1.7: Remove Debug Data from API Responses
**File:** Check if debug_data is included in JSON API responses
**Required:** Ensure debug_data never serialized in API responses
**Risk if not fixed:** Internal implementation details exposed
**Verification:** Review all serializers, controllers

---

## Phase 2: High-Priority Fixes (Days 4-10)

**Goal:** Fix HIGH severity issues that impact valuation
**Priority:** Critical for favorable due diligence outcome
**Success Criteria:** All HIGH issues resolved

### Day 4: SQL Injection Fix (Effort: 4 hours)

#### Task 2.1: Fix SQL Injection in Memory Search
**File:** `app/services/memory_search.rb` (line 147)
**Current:**
```ruby
scope.order(Arel.sql("CASE WHEN title ILIKE '#{sanitize_sql(query)}' THEN 0 ELSE 1 END, updated_at DESC"))
```
**Issue:** Custom sanitization insufficient (only handles quotes/backslashes)
**Required:** Use parameterized queries only
**Implementation:**
```ruby
# Option 1: Move ordering to Ruby
results = scope.to_a.sort_by { |m| m.title.downcase == query.downcase ? 0 : 1 }

# Option 2: Use Arel properly
relevance_order = Arel::Nodes::NamedFunction.new('CASE', [
  Arel::Nodes::When.new(
    table[:title].matches(query),
    Arel::Nodes::Quoted.new(0)
  ),
  Arel::Nodes::Else.new(Arel::Nodes::Quoted.new(1))
])
scope.order(relevance_order, updated_at: :desc)
```
**Risk if not fixed:** Data breach, unauthorized data access
**Verification:** Test with malicious input: `'; DROP TABLE memories; --`

### Day 5: Rate Limiting (Effort: 6 hours)

#### Task 2.2: Implement Rate Limiting
**File:** Create `config/initializers/rack_attack.rb`
**Current:** No rate limiting found
**Required:** Implement Rack::Attack with sensible defaults
**Implementation:**
```ruby
class Rack::Attack
  # Limit login attempts
  throttle('logins/ip', limit: 5, period: 20.seconds) do |req|
    if req.path == '/login' && req.post?
      req.ip
    end
  end

  # Limit API requests
  throttle('api/ip', limit: 100, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/api/')
  end

  # Limit conversation messages
  throttle('messages/ip', limit: 30, period: 1.minute) do |req|
    if req.path =~ %r{/conversations/\d+/messages} && req.post?
      req.ip
    end
  end
end
```
**Risk if not fixed:** DDoS vulnerability, brute force attacks
**Verification:**
```bash
# Test rate limiting
for i in {1..10}; do curl -X POST http://localhost:3000/login; done
# Expect: 429 Too Many Requests after limit
```

### Day 6-7: Security Headers (Effort: 8 hours)

#### Task 2.3: Add Security Headers Middleware
**File:** Create `app/middleware/security_headers.rb`
**Current:** No custom security headers
**Required:** Implement comprehensive security headers
**Headers to Add:**
- `X-Frame-Options: DENY` or `SAMEORIGIN`
- `X-Content-Type-Options: nosniff`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy` (various)
**Risk if not fixed:** Clickjacking, MIME sniffing attacks, information leakage
**Verification:** Check headers with `curl -I` or security scanner

### Day 8-9: Weak Password Policy (Effort: 6 hours)

#### Task 2.4: Implement Password Strength Validation
**File:** `app/models/user.rb` (add validation)
**Current:** No password strength requirements found
**Required:** Minimum 12 characters, complexity requirements
**Implementation:**
```ruby
validate :password_complexity

def password_complexity
  return unless password.present? && password.length < 12
  errors.add :password, "must be at least 12 characters"
end
```
**Risk if not fixed:** Account compromise through weak passwords
**Verification:** Try registering with weak password, verify rejection

### Day 10: Buffer/Verification Day (Effort: 4 hours)

- Run security scan (Brakeman)
- Fix any new issues discovered
- Document security improvements

---

## Phase 3: Medium-Priority Improvements (Days 11-20)

**Goal:** Address maintainability and testing gaps
**Priority:** Important for code quality assessment
**Success Criteria:** God classes refactored, test coverage improved

### Days 11-13: AIClient God Class Refactoring (Effort: 16 hours)

#### Task 3.1: Extract Prompt Building
**File:** `app/services/ai_client.rb` (lines 140-479)
**Current:** 480 lines, 19+ methods
**Extract to:** `app/services/ai/prompt_builder.rb`
**Methods to Extract:**
- `build_enhanced_system_prompt`
- `build_council_context`
- `build_expertise_context`
- `build_current_conversation_context`
- `build_memory_context`
- `build_tool_instructions`
**Risk if not fixed:** Maintainability concerns, "hard to modify" flag
**Verification:** All existing tests pass, new unit tests for PromptBuilder

#### Task 3.2: Extract Tool Handling
**Extract to:** `app/services/ai/tool_handler.rb`
**Methods to Extract:**
- `handle_tool_calls`
**Risk if not fixed:** Tight coupling, difficult testing
**Verification:** Tool handling tested independently

### Days 14-15: SpaceScribeController Refactoring (Effort: 12 hours)

#### Task 3.3: Remove Thread.current Usage
**File:** `app/controllers/space_scribe_controller.rb` (lines 43-47, 123)
**Current:** Uses Thread.current for context passing
**Required:** Pass context explicitly via method parameters
**Implementation:**
```ruby
# Instead of Thread.current[:scribe_context] = {...}
context = ToolExecutionContext.new(...)
ScribeToolExecutor.execute(tool_name, params, context)
```
**Risk if not fixed:** Hidden dependencies, thread safety issues, hard to test
**Verification:** Controller tests pass, no Thread.current usage

#### Task 3.4: Extract Service Objects
**Extract to:**
- `app/services/scribe/chat_service.rb`
- `app/services/scribe/tool_execution_service.rb`
**Risk if not fixed:** Fat controller anti-pattern
**Verification:** Controller < 100 lines

### Days 16-17: Reduce Excessive Logging (Effort: 8 hours)

#### Task 3.5: Remove Debug Logging from RoundRobinRoE
**File:** `app/services/roe/round_robin_roe.rb` (10+ log statements in 60 lines)
**Current:** Excessive logging cluttering business logic
**Required:** Remove or reduce to essential logs only
**Keep:** Error logs, warning logs
**Remove:** Most debug logs (or use block form for lazy evaluation)
**Risk if not fixed:** Log noise, performance impact in production
**Verification:** Run conversation flow, check log volume reduced

#### Task 3.6: Audit Other RoE Classes
**Files:** `app/services/roe/base_roe.rb`, `app/services/roe/moderated_roe.rb`
**Apply same treatment as Task 3.5**

### Days 18-19: Test Coverage Improvement (Effort: 12 hours)

#### Task 3.7: Add Tests for Critical Services
**Priority order:**
1. `AIClient` (extracted components)
2. `ConversationLifecycle`
3. `MemorySearch`
4. `ScribeToolExecutor`
**Target:** Minimum 70% line coverage for services
**Risk if not fixed:** "Untested code" flag during due diligence
**Verification:** `bin/rails test` coverage report

#### Task 3.8: Add Security-Focused Tests
**Tests to Add:**
- SQL injection attempts
- XSS prevention
- CSRF protection
- Authentication bypass attempts
**Risk if not fixed:** Unknown security regressions
**Verification:** Security tests pass

### Day 20: Database Indexing (Effort: 4 hours)

#### Task 3.9: Add Missing Indexes
**Analyze:** N+1 queries in conversation loading, memory searches
**Common missing indexes:**
- `messages(conversation_id, created_at)`
- `memories(space_id, memory_type, updated_at)`
- `conversations(council_id, status, last_message_at)`
**Risk if not fixed:** Performance issues at scale
**Verification:** `EXPLAIN ANALYZE` on slow queries

---

## Phase 4: Polish (Days 21-30)

**Goal:** Readability improvements, documentation, cleanup
**Priority:** Nice-to-have for code quality impression
**Success Criteria:** Code passes readability standards

### Days 21-23: Remove Console.log Statements (Effort: 6 hours)

#### Task 4.1: Remove JavaScript Console Logging
**Files:**
- `app/javascript/controllers/mentions_controller.js` (lines 11, 17)
- `app/javascript/controllers/conversation_controller.js` (line 7)
- `app/javascript/controllers/content_generator_controller.js` (lines 25, 31, 36, 51, 59, 95, 113)
- `app/javascript/controllers/prompt_generator_controller.js` (lines 21, 27, 31, 53, 60, 101, 180)
- `app/javascript/controllers/model_filter_controller.js` (lines 10, 25, 60)
**Action:** Delete or replace with proper error handling
**Risk if not fixed:** Production log pollution, unprofessional code
**Verification:** Search confirms no `console.log` in app JS

### Days 24-25: Code Cleanup (Effort: 8 hours)

#### Task 4.2: Remove Dead Code
**File:** `app/jobs/generate_advisor_response_job.rb`
**Check for:** Unused methods, commented code, unreachable branches
**Risk if not fixed:** Maintenance burden, confusion
**Verification:** Static analysis (e.g., `rails dead_code_detector`)

#### Task 4.3: Extract Magic Numbers
**File:** `app/services/ai_client.rb` (lines 9, 42, 262, 297, 316, 322)
**Current:** Magic numbers (2000, 20, 500, 300, 1000, 0.7)
**Required:** Named constants
```ruby
MAX_MEMORY_CONTEXT_LENGTH = 2000
DEFAULT_CONVERSATION_HISTORY_LIMIT = 20
MAX_DRAFT_MEMORY_DISPLAY = 500
# etc.
```
**Risk if not fixed:** Maintainability, unclear intent
**Verification:** No magic numbers in AIClient

### Days 26-27: Tool Hierarchy Consolidation (Effort: 8 hours)

#### Task 4.4: Document Tool Architecture
**Current:** Confusing parallel hierarchies (ScribeTools vs RubyLLMTools vs AdvisorTools)
**Required:** Document when to use which tool type
**Create:** `.ai/docs/patterns/tool-architecture.md`
**Risk if not fixed:** Developer confusion, wrong tool usage
**Verification:** Documentation reviewed by team

### Days 28-30: Documentation and Final Review (Effort: 12 hours)

#### Task 4.5: Security Documentation
**Create:**
- `.ai/docs/security/overview.md` - Security architecture
- `.ai/docs/security/audit-response.md` - How each audit finding was addressed

#### Task 4.6: Final Security Scan
**Run:**
```bash
bundle exec brakeman -A -w2 -q
bundle exec bundle-audit check --update
```
**Fix:** Any new issues discovered

#### Task 4.7: Code Review
**Review all changes:**
- Security fixes verified
- No regressions introduced
- Tests passing

---

## Daily Schedule Summary

| Week | Days | Focus | Key Deliverables |
|------|------|-------|-----------------|
| 1 | 1-3 | Critical Security | SSL, CSP, API keys secure |
| 2 | 4-10 | High Priority | SQL injection, rate limiting, headers |
| 3 | 11-17 | Refactoring | AIClient, SpaceScribeController split |
| 4 | 18-20 | Testing | 70% service coverage, security tests |
| 5 | 21-25 | Cleanup | Remove logs, dead code, magic numbers |
| 6 | 26-30 | Polish | Documentation, final review |

---

## Quick Wins (High Impact, Low Effort)

Complete these FIRST for immediate security improvement:

1. **Enable SSL** (Task 1.1) - 30 minutes, removes dealbreaker
2. **Filter API keys from logs** (Task 1.3) - 15 minutes, compliance
3. **Restrict debug info access** (Task 1.6) - 1 hour, closes info leak
4. **Remove console.log statements** (Task 4.1) - 2 hours, code quality
5. **Enable CSP** (Task 1.2) - 2 hours, XSS protection

**Total Quick Wins Time:** ~6 hours
**Impact:** Addresses 3 CRITICAL + 2 MEDIUM issues

---

## Dependencies and Ordering

```
Phase 1 (Days 1-3)
├── Task 1.1 (SSL) [NO DEPS] ⭐ START HERE
├── Task 1.2 (CSP) [NO DEPS] ⭐ START HERE
├── Task 1.3 (Filter params) [NO DEPS] ⭐ START HERE
├── Task 1.4 (API keys in URLs) [DEP: 1.3]
├── Task 1.5 (Session cookies) [DEP: 1.1]
└── Task 1.6 (Restrict debug) [NO DEPS]

Phase 2 (Days 4-10)
├── Task 2.1 (SQL injection) [NO DEPS]
├── Task 2.2 (Rate limiting) [NO DEPS]
├── Task 2.3 (Security headers) [DEP: 1.2]
└── Task 2.4 (Password policy) [NO DEPS]

Phase 3 (Days 11-20)
├── Task 3.1-3.2 (AIClient refactor) [NO DEPS]
├── Task 3.3-3.4 (SpaceScribe refactor) [DEP: Thread.current removal]
├── Task 3.5-3.6 (Logging cleanup) [NO DEPS]
├── Task 3.7-3.8 (Testing) [DEP: 3.1-3.4]
└── Task 3.9 (Indexes) [NO DEPS]

Phase 4 (Days 21-30)
└── All tasks have no dependencies
```

---

## Verification Steps by Task

### Security Fixes
- **SSL:** `curl -I http://site` → 301 to HTTPS
- **CSP:** Check response headers contain `Content-Security-Policy`
- **API keys:** `grep -r "api_key" log/production.log` → no matches
- **Debug info:** Login as non-admin → no debug buttons visible
- **SQL injection:** `MemorySearch.new(space, "'; DROP TABLE --").execute` → no error
- **Rate limiting:** Send 6 requests in 20 seconds → 6th returns 429
- **Session cookies:** DevTools → cookies have Secure, HttpOnly flags

### Maintainability Fixes
- **AIClient:** `wc -l app/services/ai_client.rb` → < 200 lines
- **Thread.current:** `grep -r "Thread.current" app/` → no matches
- **Test coverage:** `bin/rails test` → coverage report shows > 70% services
- **Logging:** Run conversation → log output < 50 lines

### Readability Fixes
- **Console.log:** `grep -r "console.log" app/javascript/` → no matches
- **Magic numbers:** `grep -E "\b[0-9]{3,}\b" app/services/ai_client.rb` → only constants
- **Dead code:** Static analysis → no unused methods

---

## Success Criteria

### Phase 1 Success
- [ ] `config.force_ssl = true` uncommented and deployed
- [ ] CSP headers present in all responses
- [ ] API keys filtered from all logs
- [ ] API keys never appear in URLs
- [ ] Session cookies have Secure, HttpOnly, SameSite flags
- [ ] Debug info only visible to admins

### Phase 2 Success
- [ ] SQL injection vulnerability patched and tested
- [ ] Rate limiting active (verify with curl)
- [ ] Security headers present on all responses
- [ ] Password strength validation enforced
- [ ] Brakeman scan shows 0 HIGH/CRITICAL issues

### Phase 3 Success
- [ ] AIClient < 200 lines (from 480)
- [ ] SpaceScribeController < 150 lines (from 315)
- [ ] No Thread.current usage in codebase
- [ ] Service test coverage > 70%
- [ ] Security tests passing
- [ ] Database indexes added for common queries

### Phase 4 Success
- [ ] No console.log in production JS
- [ ] No dead code identified
- [ ] All magic numbers extracted to constants
- [ ] Tool architecture documented
- [ ] Security documentation complete
- [ ] Final Brakeman scan: 0 issues

---

## Rollback Plan

### If Critical Issues Cannot Be Fixed

1. **SSL/CSP cannot be enabled:**
   - Document why (e.g., legacy client requirements)
   - Implement alternative mitigations (WAF, network segmentation)
   - Prepare explanation for due diligence team

2. **API key exposure cannot be fully resolved:**
   - Implement key rotation policy
   - Add detection for exposed keys
   - Document temporary workaround

3. **Timeline at risk:**
   - Focus only on CRITICAL + highest impact HIGH issues
   - Defer refactoring to post-due diligence
   - Document technical debt for new owners

### Rollback Commands

If any change causes production issues:

```bash
# Revert specific file
git checkout HEAD -- config/environments/production.rb

# Revert entire phase
git reset --hard <phase-start-commit>

# Emergency rollback to pre-plan state
git checkout pre-due-diligence-improvements
```

---

## Doc Impact

- **Updated:** `.ai/docs/security/overview.md` (to be created)
- **Updated:** `.ai/docs/security/audit-response.md` (to be created)
- **Updated:** `.ai/MEMORY.md` (security invariants)
- **Updated:** `.ai/docs/patterns/tool-architecture.md` (to be created)
- **None:** Feature documentation (no user-facing changes)

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Refactoring introduces bugs | Medium | High | Comprehensive tests before refactoring |
| Security fixes break features | Low | High | Staging environment testing |
| Timeline slips | Medium | Medium | Prioritize CRITICAL only if needed |
| Due diligence moves up | Low | Severe | Phase 1 can complete in 3 days |
| Builder unfamiliar with codebase | Medium | Medium | Detailed task instructions provided |

---

## Unknowns

1. **Staging environment availability:** Need production-like environment for security testing
2. **SSL certificate status:** May need certificate procurement if not already in place
3. **WAF/CDN configuration:** May affect security header implementation
4. **Third-party API restrictions:** Rate limiting may need adjustment based on legitimate usage

---

## Approval Request

**This plan requires explicit approval before implementation.**

Please review and confirm:
1. [ ] Priority order is correct (CRITICAL first)
2. [ ] Timeline is achievable (30 days)
3. [ ] Resource allocation is approved
4. [ ] Rollback plan is acceptable

**Approval:** _________________  **Date:** _________________

---

## Appendix: Evidence Summary

### Files Inspected
- `config/environments/production.rb` - SSL disabled (line 31)
- `config/initializers/content_security_policy.rb` - CSP disabled (all commented)
- `config/initializers/filter_parameter_logging.rb` - Missing api_key filter (line 7)
- `app/controllers/providers_controller.rb` - API keys in URLs (lines 70, 75)
- `app/services/ai_client.rb` - God class (480 lines, 19 methods)
- `app/controllers/space_scribe_controller.rb` - Thread.current usage (lines 43-47, 123)
- `app/services/roe/round_robin_roe.rb` - Excessive logging (10+ statements)
- `app/services/memory_search.rb` - SQL injection (line 147)
- `app/views/messages/_message.html.erb` - Debug info exposed (lines 84-118)
- JavaScript files - console.log statements (5 files)

### Commands Run
- `find app/services -name "*.rb" -exec wc -l {} +` - Service code: 8,058 lines
- `find test -name "*.rb" -exec wc -l {} +` - Test code: ~2,500 lines
- `grep -r "console.log" app/javascript/` - 5 files with console.log
- `grep -r "rack.attack\|rate.limit" config/` - No rate limiting found
- `grep -n "add_index" db/schema.rb` - Existing indexes cataloged

### Security Scan Results
- Brakeman: Not yet run (to be executed in Phase 2)
- Bundle audit: Not yet run (to be executed in Phase 2)
