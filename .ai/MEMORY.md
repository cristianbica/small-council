# Memory (curated)

Max ~200 lines. Keep durable, high-signal facts only.

## Commands (verified 2026-03-05)
- Install check: `bundle check` (dependencies satisfied)
- Targeted test: `bin/rails test test/models/conversation_test.rb` (32 runs, 0 failures)
- Dev startup smoke: `timeout 12s bin/dev` (web + css booted; timeout sends SIGTERM)
- Run (Rails only): `bin/rails server`
- Full suite entrypoint: `bin/rails test`
- Lint entrypoint: `bin/rubocop`

## URLs (development)
- Sign in: http://localhost:3000/sign_in
- Sign up: http://localhost:3000/sign_up
- Dashboard: http://localhost:3000/dashboard

## Demo credentials
- Email: `demo@example.com`
- Password: `password123`
- Seed source: `bin/rails db:seed`

## Architecture + invariants
- Multi-tenancy is enforced with `acts_as_tenant`; `ApplicationController` sets `Current.account` and `ActsAsTenant.current_tenant`.
- `Current.space` is restored from `session[:space_id]`, falls back to first account space, and auto-creates `General` for legacy accounts.
- `Conversation` requires `space`; statuses are `active|resolved|archived`; types are `council_meeting|adhoc`; RoE is `open|consensus|brainstorming`.
- Advisor names are canonical lowercase dash handles; mentions/invites must use this handle format.
- Messages use polymorphic sender (`User`/`Advisor`) and track turn state with `pending_advisor_ids` + status (`pending|responding|complete|error|cancelled`).
- Sensitive fields are encrypted at rest (`Provider.credentials`, `Advisor.system_prompt/short_description`, `Conversation.memory/draft_memory`, `Message.content/prompt_text`, `Memory.content`).

## AI stack
- `AI::Client` is instance-based for chat/complete, with class methods for provider operations (`test_connection`, `list_models`).
- Supported providers: `openai`, `openrouter`.
- Usage is tracked automatically in `AI::Client#track_usage` via `UsageRecord`.
- Model interactions are recorded via RubyLLM event handlers wired in `AI::Client#register_interaction_handler`.
- Tool framework is `AI::Tools::BaseTool` + `AI::Adapters::RubyLLMToolAdapter`.
- Tool inventory: 22 files total (`internal`: 19, `external`: 1, `conversations`: 1, `base_tool`: 1).
- Current wiring in `AI::ContentGenerator#advisor_tools`: non-scribe advisors get no tools; Scribe gets 20 tools; `AskAdvisorTool` exists but is not wired.

## Testing conventions
- Use `set_tenant(account)` in model/unit tests for tenant-scoped models.
- For request/integration tests, set host explicitly when host behavior matters.
- Stub current user via `Current.session = stub(user: user)` (not `Current.user = ...`).
- For AI client tests, stub `AI::Client.new` then stub instance `#chat`.
- System tests use Cuprite/Ferrum in `ApplicationSystemTestCase`; optional `CHROME_URL` for remote browser.

## Repo layout
- Main app code: `app/`
- AI code: `app/libs/ai/`
- Tests: `test/`
- Config: `config/`
- Context docs: `.ai/docs/`
