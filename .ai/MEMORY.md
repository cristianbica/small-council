# Memory (curated)

Max ~200 lines. Keep durable, high-signal facts only.

## Commands (verified 2026-03-02)
- Install check: `bundle check` (dependencies satisfied)
- Build: `bin/rails assets:precompile` (succeeds; Tailwind emits `@property` warning)
- Test: `bin/rails test` (runs 1420 tests; currently 11 failures)
- Lint: `bin/rubocop` (currently 3 offenses)
- Run (Rails only): `bin/rails server`
- Dev server: `bin/dev` (foreman web + css watch; fails if stale `tmp/pids/server.pid` exists)
- DB migrate: `bin/rails db:migrate`
- DB reset: `bin/rails db:reset`
- DB seed: `bin/rails db:seed` (demo user)
- CSS build: `bin/rails tailwindcss:build`
- CSS watch: `bin/rails tailwindcss:watch`

## URLs (development)
- Sign in: http://localhost:3000/sign_in
- Sign up: http://localhost:3000/sign_up
- Dashboard: http://localhost:3000/dashboard

## Demo credentials
- Email: `demo@example.com`
- Password: `password123`
- Created by: `bin/rails db:seed`

## Architecture + invariants
- Multi-tenancy is enforced with `acts_as_tenant`; app data is account-scoped.
- `Conversation` belongs to `space` (required), and `Current.space` is used for access scoping in controllers/jobs.
- Conversation statuses are `active`, `resolved`, `archived`.
- Conversation RoE types are `open`, `consensus`, `brainstorming`.
- Messages use polymorphic sender (`User` or `Advisor`) and `pending_advisor_ids` JSONB for response tracking.
- Sensitive fields are encrypted at rest (e.g., provider credentials, conversation memory fields, advisor prompts).

## AI stack
- `AI::Client` is instance-based for chat, with class methods for provider operations (`test_connection`, `list_models`).
- Supported provider types: `openai`, `openrouter`.
- Usage tracking is automatic in `AI::Client#track_usage` via `UsageRecord`.
- Model interactions are captured via RubyLLM event handlers in `AI::Client#register_interaction_handler`.
- Tool framework uses `AI::Tools::BaseTool` under `app/libs/ai/tools/` with adapter `AI::Adapters::RubyLLMToolAdapter`.
- Tool classes present: 22 (`internal`: 19, `external`: 1, `conversations`: 1, `base_tool`: 1).
- Current wiring in `AI::ContentGenerator#advisor_tools`: 8 read-only tools for all advisors + 12 additional tools for Scribe; `AskAdvisorTool` exists but is not currently wired.

## Testing conventions
- Use `set_tenant(account)` in model/unit tests for tenant-scoped models.
- For request/integration tests, set host explicitly (for APP_HOST/tenant host behavior).
- Stub current user via `Current.session = stub(user: user)` (not `Current.user = ...`).
- For AI client tests, stub `AI::Client.new` and then stub instance `#chat`.

## Repo layout
- Main app code: `app/`
- AI code: `app/libs/ai/`
- Tests: `test/`
- Config: `config/`
- Context docs: `.ai/docs/`
