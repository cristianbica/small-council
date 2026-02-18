# Memory (curated)

Max ~200 lines. Prune oldest/least-used when full. One agent updates per session to avoid conflicts.

## Commands (verified)
- Build: `bin/rails assets:precompile`
- Test: `bin/rails test`
- Run: `bin/rails server`
- Dev server: `bin/dev` (runs web + CSS watch via foreman)
- DB migrate: `bin/rails db:migrate`
- DB reset: `bin/rails db:reset`
- DB seed: `bin/rails db:seed` (creates demo user)
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

## Conventions
- File naming: snake_case for files, PascalCase for classes
- acts_as_tenant is active on all scoped models
- JSONB columns use GIN indexes for queryability
- NEVER edit Rails-owned files directly (use `.custom.rb` counterparts)

## Test helpers
- `sign_in_as(user, password: "password123")` - authenticate in integration tests
- `sign_out` - destroy current session in tests
- `host! ENV["APP_HOST"]` if present - set test request host to match APP_HOST config
- Demo user fixtures: `users(:one)`, `users(:admin)`
- `set_tenant(account)` - set ActsAsTenant current_tenant in model tests

Note: Rails integration tests default to `www.example.com` which may not be in allowed hosts. Using `host!` ensures tests use a host that matches config (required with acts_as_tenant).

## Invariants (non-negotiable)
- All tables except accounts have account_id for multi-tenancy
- Tenant scoping is active via acts_as_tenant gem (all queries automatically scoped)
- Messages use polymorphic sender (User or Advisor)
- Usage tracking records all AI API calls with tokens and cost
- User emails are globally unique (database unique index on users.email)
- **Encryption at rest**: All sensitive conversation data encrypted (messages.content, conversations.memory/draft_memory, advisors.system_prompt)

## Repo layout
- Main code: `app/` (models, controllers, views, jobs)
- Tests: `test/` (models, controllers, integration)
- Config: `config/` (routes, database, initializers)
- Docs: `.ai/docs/` (feature docs, patterns)

## Business domains
- Multi-tenant AI advisor platform
- Spaces: contextual workspaces containing councils
- Councils: groups of AI advisors that collaborate
- Conversations: chat sessions with advisor participation
- Advisors: AI personas with configurable LLM models
- Usage tracking: per-account billing and observability
- AI Providers: OpenAI, Anthropic, GitHub Models with encrypted API credentials
- LlmModels: Per-account model configuration (GPT-4, Claude, etc.)

## Data Layer (2026-02-18)
- 11 migrations, 11 models
- Key tables: accounts, users, spaces, advisors, councils, council_advisors, conversations, messages, usage_records, providers, llm_models
- acts_as_tenant gem is enabled and active (automatic tenant scoping on all queries)
- JSONB columns: settings, preferences, model_config, metadata, configuration, content_blocks, context, custom_prompt_override, credentials
- GIN indexes on all JSONB columns
- Polymorphic sender on messages table (sender_type, sender_id)
- Encrypted credentials: `Provider.credentials` uses Rails encrypted attributes for API keys
- Current attributes: `Current.session`, `Current.user`, `Current.account`, `Current.space`

## Discovered quirks
- 2026-02-10: Initialized `.ai/` template structure and core roles/workflows.
- 2026-02-18: Data layer implemented with acts_as_tenant gem active (automatic query scoping).
- 2026-02-18: Tenant setting uses `Current.user.account` pattern via `set_current_tenant` filter.
- 2026-02-18: Spaces feature - Contextual workspaces containing councils, with session-based space switching.
- 2026-02-18: Conversations Phase 1 - Chat UI with list, create, view, and post messages.
- 2026-02-18: Conversations Phase 2 - Rules of Engagement (RoE) with 5 modes: round_robin, moderated, on_demand, silent, consensus.
- 2026-02-18: AI Integration - Multi-provider LLM support (OpenAI, Anthropic, GitHub Models) with encrypted credentials, async job processing, Turbo Streams real-time updates, and usage tracking.
- 2026-02-18: RoE-based Conversation Auto-Conclusion - Conversations can auto-conclude based on Rules of Engagement mode (Consensus, Round Robin, Moderated) or manual finish (On Demand, Silent). Statuses: active → concluding → resolved → archived.
- 2026-02-18: Active Record encryption uses deterministic test keys in test environment.
- 2026-02-18: Security test audit added 37 new security tests covering tenant isolation, parameter tampering, mass assignment, and cross-account access. See `.ai/docs/patterns/security-testing.md` for patterns.
- 2026-02-18: Conversation Memory Features - Structured AI-generated summaries with key decisions, action items, insights, and open questions. Space-level cumulative memory browser with search. Regenerate summary option available during review.

## Gems
- `ruby-openai` (~> 7.0) - OpenAI API client
- `anthropic` (~> 0.3) - Anthropic API client
- `mocha` - Test mocking (for service/job tests with any_instance/stubs)
- `acts_as_tenant` - Multi-tenancy (automatic account scoping)
- `simplecov` - Code coverage analysis (test group only, configured in test_helper.rb)

## UI Framework (2026-02-18)
- Tailwind CSS v4.1.18 via `tailwindcss-rails` gem (no Node.js)
- DaisyUI v5.5.18 for component classes (downloaded as .mjs plugin)
- Config: `app/assets/tailwind/application.css`
- Output: `app/assets/builds/tailwind.css`
- Theme: `data-theme="light"` on html tag
- Key DaisyUI classes: btn, card, navbar, alert, form-control, input, menu

## Configuration Pattern (2026-02-18)
- NEVER edit Rails-owned files directly (`config/application.rb`, `config/environments/*.rb`)
- Always use `.custom.rb` counterparts for app-specific overrides that survive Rails upgrades
- `config/application.custom.rb` - global hooks (gitignored, copy from .example)
- `config/environments/*.custom.rb` - environment overrides (gitignored)
- `.example` files are tracked in git as templates
- Load order: application.rb → application.custom.rb → environment.rb → environment.custom.rb
- Test helpers should set `host!` to match APP_HOST pattern
- dotenv-rails: dev/test only (production uses system ENV vars)
- Required ENV vars for production: APP_HOST (optional), RAILS_LOG_LEVEL (optional, defaults to info)
