# Plan: Re-verification & Coverage Improvement

## Status: COMPLETED (2026-02-28)
- 0 failures, 0 errors
- Line coverage: 96.71%
- Branch coverage: 85.21%

Date: 2026-02-28

## Goal

- Fix 6 failing tests caused by a mock mismatch in `ProviderConnectionTester` tests
- Raise branch coverage from 77.87% toward ≥85% by targeting specific low-coverage files
- Refresh stale `.ai/docs/` entries that reference the old `LLM::Client` / `AIClient` architecture

## Non-goals

- Full integration tests that make real API calls
- 100% branch coverage on every file
- Refactoring production code (test-only changes unless a bug is found)

## Scope + assumptions

- All commands run from `/root/p/small-council`
- SimpleCov is already configured in `test_helper.rb`
- Coverage numbers come from the 2026-02-28 test run: **93.3% line / 77.87% branch**
- The failing tests are in `ProviderConnectionTester` and `ProvidersWizard`; they are all mock-mismatch issues, not production bugs

---

## Section 1 — Test Suite Status

### Run summary (2026-02-28)

| Metric | Value |
|--------|-------|
| Total tests | 1364 |
| Assertions | 3876 |
| Failures | **6** |
| Errors | 0 |
| Skips | 3 |
| Line coverage | 93.3% |
| Branch coverage | 77.87% |

### Failures

All 6 failures live in two files and share **one root cause**: tests mock `AI::Client.new` (returning a mock with instance methods `test_connection` / `list_models`), but `ProviderConnectionTester.test` calls the **class methods** `AI::Client.test_connection(provider:)` and `AI::Client.list_models(provider:)`.

| # | Test (file:line) | Root cause |
|---|-----------------|------------|
| 1 | `ProviderConnectionTesterTest#test_openai_returns_success` (line 19) | Should mock `AI::Client.stubs(:test_connection)` + `AI::Client.stubs(:list_models)`, not `.new` |
| 2 | `ProviderConnectionTesterTest#test_openai_includes_organization_id` (line 37) | Same |
| 3 | `ProviderConnectionTesterTest#test_openai_handles_connection_errors` (line 49) | Same |
| 4 | `ProviderConnectionTesterTest#test_openrouter_returns_success` (line 61) | Same |
| 5 | `ProviderConnectionTesterTest#test_openrouter_handles_errors` (line 78) | Same |
| 6 | `ProvidersWizardTest#test_should_test_connection_via_AJAX` (line 78) | Same root cause: controller calls `ProviderConnectionTester.test` → `AI::Client.test_connection` (class), but stub targets `.new` |

### Skips (3)

Skipped tests are non-blocking. Run with `--verbose` to identify them if needed.

---

## Section 2 — Coverage Summary

**Line: 93.3% | Branch: 77.87%**

### Files with branch coverage < 70% (highest-impact targets)

| File | Branch % | Uncovered lines | Priority |
|------|----------|-----------------|----------|
| `app/libs/ai/model_manager.rb` | 0.0% | 91 | HIGH |
| `app/models/llm_model.rb` | 0.0% | 115 | HIGH |
| `app/helpers/application_helper.rb` | 22.2% | 32 | MEDIUM |
| `app/models/council.rb` | 30.0% | 82 | HIGH |
| `app/models/memory_version.rb` | 42.9% | 69 | MEDIUM |
| `app/libs/ai/adapters/ruby_llm_tool_adapter.rb` | 50.0% | 78 | MEDIUM |
| `app/helpers/markdown_helper.rb` | 50.0% | 15 | LOW |
| `app/models/provider.rb` | 50.0% | 45 | MEDIUM |
| `app/models/space.rb` | 50.0% | 84 | HIGH |
| `app/models/user.rb` | 50.0% | 28 | MEDIUM |
| `app/services/provider_connection_tester.rb` | 50.0% | 21 | MEDIUM |
| `app/jobs/generate_advisor_response_job.rb` | 57.1% | 167 | HIGH |
| `app/helpers/memories_helper.rb` | 60.0% | 17 | LOW |
| `app/libs/ai/context_builders/base_context_builder.rb` | 60.0% | 141 | MEDIUM |
| `app/libs/ai/content_generator.rb` | 61.1% | 443 | HIGH |
| `app/controllers/providers_controller.rb` | 62.5% | 230 | MEDIUM |
| `app/models/memory.rb` | 63.2% | 241 | HIGH |
| `app/libs/ai/context_builders/conversation_context_builder.rb` | 66.7% | 86 | MEDIUM |

### Files between 70–80% (secondary targets)

| File | Branch % |
|------|----------|
| `app/libs/ai/client.rb` | 70.6% |
| `app/controllers/sessions_controller.rb` | 75.0% |
| `app/libs/ai/tools/conversations/summarize_conversation_tool.rb` | 78.6% |
| `app/libs/ai/tools/internal/list_conversations_tool.rb` | 78.6% |

---

## Section 3 — Targeted Coverage Improvements

### Fix 1 — `ProviderConnectionTesterTest` (5 tests) + `ProvidersWizardTest` (1 test)

**File:** `test/services/provider_connection_tester_test.rb`
**File:** `test/integration/providers_wizard_test.rb`

**Change:** Replace mocks of `AI::Client.expects(:new)` with class-method stubs:

```ruby
# WRONG (current):
AI::Client.expects(:new).returns(mock_client)
mock_client.expects(:test_connection).returns(...)
mock_client.expects(:list_models).returns(...)

# CORRECT:
AI::Client.stubs(:test_connection).returns({ success: true, model: "gpt-4o-mini" })
AI::Client.stubs(:list_models).returns([{ id: "gpt-4", name: "GPT-4", provider: "openai" }])
```

Apply to all 5 `ProviderConnectionTesterTest` tests that mock the AI client, and the `ProvidersWizardTest#test_should_test_connection_via_AJAX` test.

---

### Fix 2 — `app/models/council.rb` (30% branch → target 75%)

**File:** `test/models/council_test.rb`

Missing test cases (branches in `ensure_scribe_assigned`, `create_conversation!`, `scribe_advisor`):

1. `ensure_scribe_assigned` — when no scribe exists in space → should not raise
2. `ensure_scribe_assigned` — when scribe already in council → should not create duplicate
3. `ensure_scribe_assigned` — when scribe exists in space but not in council → should add scribe
4. `create_conversation!` — with `initial_message` present → message is created
5. `create_conversation!` — with `initial_message` nil → no message created
6. `create_conversation!` — with scribe advisor in council → participant role is "scribe"
7. `create_conversation!` — with non-scribe advisor → participant role is "advisor"
8. `available_advisors` — delegates to `space.non_scribe_advisors`

---

### Fix 3 — `app/models/space.rb` (50% branch → target 80%)

**File:** `test/models/space_test.rb`

Missing test cases (branches in `scribe_advisor`, `create_scribe_advisor` callback):

1. `scribe_advisor` — when scribe already exists → returns existing scribe (no new creation)
2. `scribe_advisor` — when no scribe exists → creates and returns new scribe
3. `create_scribe_advisor` (after_create) — when no LLM model available → logs error, does not raise
4. `create_scribe_advisor` (after_create) — uses `default_llm_model` if available
5. `create_scribe_advisor` (after_create) — falls back to `enabled.first` if no default
6. `non_scribe_advisors` — returns only non-scribe advisors

---

### Fix 4 — `app/models/llm_model.rb` (0% branch → target 70%)

**File:** `test/models/llm_model_test.rb`

Missing test cases (capability methods, `sync_from_ruby_llm!`, `supports_*?` branching):

1. `supports_chat?` — true when `capabilities["chat"]` is true
2. `supports_chat?` — false when capabilities hash is empty
3. `supports_vision?` — true when metadata contains `"vision": true`
4. `supports_json_mode?` — true when `capabilities["json_mode"]` is true
5. `supports_functions?` — true when `capabilities["functions"]` is true
6. `supports_streaming?` — true when `capabilities["streaming"]` is true
7. `input_price` / `output_price` — returns 0.0 when metadata is empty
8. `sync_from_ruby_llm!` — when `api.info` returns nil → returns without updating
9. `sync_from_ruby_llm!` — when pricing is blank → `free` defaults to false
10. `sync_from_ruby_llm!` — when pricing is present and both 0.0 → `free` is true
11. `scope :free` — returns only free models
12. `scope :paid` — returns only non-free models

---

### Fix 5 — `app/libs/ai/model_manager.rb` (0% branch → target 70%)

**File:** `test/ai/unit/model_manager_test.rb` (new file)

Missing test cases:

1. `available_models` — with no enabled providers → returns empty array
2. `available_models` — with enabled provider → maps models with enabled status
3. `available_models` — `enabled` flag false when LLMModel not found for a model_id
4. `enable_model` — when `api.info` returns nil → falls back to name from model_id
5. `enable_model` — when `api.info` returns data → stores full metadata, capabilities, pricing
6. `enable_model` — sets `free: true` when both input/output prices are 0.0
7. `enable_model` — creates new record with `find_or_initialize_by`
8. `enable_model` — updates existing record if already exists
9. `disable_model` — when model not found → returns nil (no-op)
10. `disable_model` — when model found → sets enabled: false

---

### Fix 6 — `app/models/memory.rb` (63.2% branch → target 85%)

**File:** `test/models/memory_test.rb`

Missing test cases (branches in `source_display`, `creator_display`, versioning):

1. `source_display` — when source is nil → returns nil
2. `source_display` — when source is a Conversation → returns "Conversation: {title}"
3. `source_display` — when source is other type → returns `.to_s`
4. `creator_display` — when `created_by` is nil → returns "Unknown"
5. `creator_display` — when `created_by` is a User → returns email
6. `creator_display` — when `created_by` is an Advisor → returns name
7. `create_conversation_summary!` — creates with correct space from council
8. `create_conversation_notes!` — creates with correct space from council
9. `restore_version!` — when version_number not found → returns nil
10. `restore_version!` — when found → calls `version.restore_to_memory!`
11. `create_initial_version` (after_create) — version is created with change_reason "Initial creation"
12. `create_initial_version` rescue path — logs error, does not propagate

---

### Fix 7 — `app/jobs/generate_advisor_response_job.rb` (57.1% branch → target 80%)

**File:** `test/jobs/generate_advisor_response_job_test.rb`

Missing test cases (branches in space resolution, scribe path):

1. `is_scribe_followup: true` → calls `generate_scribe_followup` instead of `generate_advisor_response`
2. `is_scribe_followup: false` with scribe advisor → calls `generate_advisor_response`
3. Space resolution: `council_meeting?` conversation → uses `conversation.council.space`
4. Space resolution: adhoc conversation with advisor.space set → uses `advisor.space`
5. Space resolution: adhoc with no advisor.space → uses first participant's space
6. `calculate_cost_from_tokens` with `anthropic` provider → uses Anthropic rates
7. `create_usage_record_from_response` — when no model → skips usage record creation

---

### Fix 8 — `app/libs/ai/context_builders/base_context_builder.rb` (60% branch → target 80%)

**File:** `test/ai/unit/context_builders/base_context_builder_test.rb`

Missing test cases:

1. `recent_memories` — when space is nil → returns `[]`
2. `recent_conversations` — when space is nil → returns `[]`
3. `recent_conversations` — when conversation set → excludes current conversation
4. `space_advisors` — when space is nil → returns `[]`
5. `conversation_advisors` — when conversation is nil → returns `[]`
6. `council` — when conversation is adhoc → returns nil
7. `effective_space` — when space is nil but council_meeting with council → returns council.space
8. `effective_space` — when both nil → returns nil
9. `roe_description` — for each of `open`, `consensus`, `brainstorming`, and unknown type
10. `validate_space!` — adhoc conversation without council → raises ArgumentError

---

### Fix 9 — `app/helpers/application_helper.rb` (22.2% branch → target 90%)

**File:** `test/helpers/application_helper_test.rb` (new file or add to existing)

Missing test cases:

1. `status_badge_class` — each of: `active`, `concluding`, `resolved`, `archived`, unknown
2. `can_finish_conversation?` — when user is conversation starter AND conversation is active → true
3. `can_finish_conversation?` — when user is council creator AND conversation active → true
4. `can_finish_conversation?` — when user is neither → false
5. `can_finish_conversation?` — when conversation is not active → false
6. `can_delete_conversation?` — when user is conversation starter → true
7. `can_delete_conversation?` — when user is council creator → true
8. `can_delete_conversation?` — when user is neither → false

---

## Section 4 — Docs Refresh List

| File | Status | Required changes |
|------|--------|-----------------|
| `.ai/docs/features/ai-integration.md` | **STALE** | References `LLM::Client` (old module), `AIClient` service, `ScribeCoordinator`, `LLM::Client::MissingModelError`. Actual code is `AI::Client`, `AI::ContentGenerator`, `AI::ModelManager`. Update entire architecture section and all code examples. |
| `.ai/docs/features/data-model.md` | **STALE** | References old advisor fields (`model_provider`, `model_id`, `model_config`) and old conversations schema (missing `conversation_type`, `roe_type`, `scribe_initiated_count`). Missing `conversation_participants`, `memories`, `memory_versions` tables. |
| `.ai/docs/patterns/tool-system.md` | **STALE** | References old `app/services/scribe_tools/`, `advisor_tools/`, `ruby_llm_tools/` layout and `ScribeToolExecutor`. Actual code is `app/libs/ai/tools/` with `AI::Tools::BaseTool`, `AI::Adapters::RubyLLMToolAdapter`. |
| `.ai/docs/overview.md` | **MINOR** | Shows "565 tests, ~48% coverage" (line 21) and "455 tests" (line 60) — both wrong. Update to 1364 tests, 93.3% line / 77.87% branch. Also lists 10 models but there are 12 now (Memory, MemoryVersion). Update `app/services/` entry from `AIClient, ScribeCoordinator` to `ConversationLifecycle, AI::ContentGenerator`. |
| `.ai/docs/patterns/testing.md` | **MINOR** | Only 5 lines — expand with actual test conventions from MEMORY.md (mock patterns, `AI::Client` class-method stubs, `set_tenant`, `host!`, fixture names). |

---

## Steps

1. **Fix failing tests** — Update mock style in `test/services/provider_connection_tester_test.rb` (5 tests) and `test/integration/providers_wizard_test.rb` (1 test). Replace `AI::Client.expects(:new).returns(mock)` + instance-method stubs with `AI::Client.stubs(:test_connection).returns(...)` and `AI::Client.stubs(:list_models).returns(...)`.

2. **Add council model tests** — Add 8 test cases to `test/models/council_test.rb` targeting `ensure_scribe_assigned`, `create_conversation!` branches, and advisor roles (Fix 2).

3. **Add space model tests** — Add 6 test cases to `test/models/space_test.rb` targeting `scribe_advisor`, `create_scribe_advisor` callback branches (Fix 3).

4. **Add LlmModel capability tests** — Add 12 test cases to `test/models/llm_model_test.rb` targeting `supports_*?` methods, `sync_from_ruby_llm!` branches, and price/free scopes (Fix 4).

5. **Create ModelManager unit tests** — Create `test/ai/unit/model_manager_test.rb` with 10 test cases (Fix 5). Use Mocha to stub `AI::Client.list_models` and `AI::Client.new(...).info`.

6. **Add memory model tests** — Add 12 test cases to `test/models/memory_test.rb` targeting display methods, version creation, and class-method branches (Fix 6).

7. **Add job branch tests** — Add 7 test cases to `test/jobs/generate_advisor_response_job_test.rb` targeting scribe path, space resolution, and cost calculation branches (Fix 7).

8. **Add context builder tests** — Add 10 test cases to `test/ai/unit/context_builders/base_context_builder_test.rb` (Fix 8).

9. **Add application helper tests** — Create `test/helpers/application_helper_test.rb` with 8 test cases covering all branches of `status_badge_class`, `can_finish_conversation?`, and `can_delete_conversation?` (Fix 9).

10. **Refresh docs** — Update `.ai/docs/features/ai-integration.md`, `.ai/docs/features/data-model.md`, `.ai/docs/patterns/tool-system.md`, `.ai/docs/overview.md`, and `.ai/docs/patterns/testing.md` per Section 4 above.

---

## Verification

```bash
# After each step:
bin/rails test 2>&1 | tail -10
# Expected: 0 failures, 0 errors

# After all steps:
bin/rails test 2>&1 | grep -E "failures|Branch Coverage|Line Coverage"
# Expected: 0 failures, Branch Coverage > 85%, Line Coverage > 93%
```

---

## Doc impact

- Update: `.ai/docs/features/ai-integration.md`
- Update: `.ai/docs/features/data-model.md`
- Update: `.ai/docs/patterns/tool-system.md`
- Update: `.ai/docs/overview.md`
- Update: `.ai/docs/patterns/testing.md`

---

## Rollback

Tests-only and docs-only changes. No production code changes. Rollback = `git revert` or simply delete added test cases.
