# Memory (curated)

Max ~200 lines. Keep durable, high-signal facts only.

## Commands (verified 2026-03-11)
- Install check: `bundle check` (pass)
- Install: `bundle install` (pass)
- Build: `bin/rails assets:precompile` (pass; Tailwind/daisyUI emits known `@property` warning)
- Test: `bin/rails test` (pass: 1195 runs, 0 failures, 0 errors, 3 skips)
- Lint: `bin/rubocop` (fail: 1 trailing-comma offense in `app/models/conversation.rb`)
- Dev smoke: `timeout 12s bin/dev` (blocked: existing `tmp/pids/server.pid`)
- Run smoke: `timeout 10s bin/rails server` (blocked: existing `tmp/pids/server.pid`)

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
- Conversation auto-title is callback-driven in `Conversation` and uses `AI.run` (`conversations/title_generator` + `conversations/update_conversation` tool), guarded by `title_state` transitions.
- Advisor names are canonical lowercase dash handles; mentions/invites must use this handle format.
- Messages use polymorphic sender (`User`/`Advisor`) and track turn state with `pending_advisor_ids` + status (`pending|responding|complete|error|cancelled`).
- `Message.message_type` distinguishes normal chat (`chat`) from conversation compaction (`compaction`); `Conversation#chat_blocked?` is derived from active compaction messages.
- Sensitive fields are encrypted at rest (`Provider.credentials`, `Advisor.system_prompt/short_description`, `Conversation.memory/draft_memory`, `Message.content/prompt_text`, `Memory.content`).

## Versioning
- Versioning is handled by `Versionable` concern using `RecordVersion` model with jsonb storage.
- Versions store PREVIOUS state via `before_commit` callback; linked by `previous_version_id`.
- Context flows through `Current.version_whodunnit` (polymorphic, defaults to `Current.user`) and `Current.version_metadata`.
- Enable on a model: `include Versionable` + `track_versions :attr1, :attr2`.

## AI stack
- `AI::Client` is class-based for chat session creation (`AI::Client.chat`) and provider/model operations (`test_connection`, `list_models`, `model_info`).
- Supported providers: `openai`, `openrouter`.
- Canonical async runtime path is `AI::Runner` via `AIRunnerJob` (`task` + `context` + optional `handler` or `tracker`) for normal advisor responses and retries.
- Model interactions are recorded by `AI::Trackers::ModelInteractionTracker` callback hooks and mirrored to `messages.tool_calls`.
- Tool framework is `AI::Tools::AbstractTool` with registry-based resolution (`AI.tool` / `AI.tools`) and direct RubyLLM tool subclasses.

## Testing conventions
- Use `set_tenant(account)` in model/unit tests for tenant-scoped models.
- For request/integration tests, set host explicitly when host behavior matters.
- Stub current user via `Current.session = stub(user: user)` (not `Current.user = ...`).
- For AI client tests, exercise `AI::Client.chat` / `AI::Client::Chat` and stub provider chat objects as needed.

## Repo layout
- Main app code: `app/`
- AI code: `app/libs/ai/`
- Tests: `test/`
- Config: `config/`
- Context docs: `.ai/docs/`
