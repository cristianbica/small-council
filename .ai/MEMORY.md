# Memory (curated)

Max ~200 lines. Prune oldest/least-used when full. One agent updates per session to avoid conflicts.

## Commands (verified)
- Build: `bin/rails assets:precompile`
- Test: `bin/rails test`
- Run: `bin/rails server`
- DB migrate: `bin/rails db:migrate`
- DB reset: `bin/rails db:reset`
- DB seed: `bin/rails db:seed` (creates demo user)

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
- Model comments indicate future acts_as_tenant activation
- JSONB columns use GIN indexes for queryability

## Test helpers
- `sign_in_as(user, password: "password123")` - authenticate in integration tests
- `sign_out` - destroy current session in tests
- Demo user fixtures: `users(:one)`, `users(:admin)`

## Invariants (non-negotiable)
- All tables except accounts have account_id for multi-tenancy
- Messages use polymorphic sender (User or Advisor)
- Usage tracking records all AI API calls with tokens and cost

## Repo layout
- Main code: `app/` (models, controllers, views, jobs)
- Tests: `test/` (models, controllers, integration)
- Config: `config/` (routes, database, initializers)
- Docs: `.ai/docs/` (feature docs, patterns)

## Business domains
- Multi-tenant AI advisor platform
- Councils: groups of AI advisors that collaborate
- Conversations: chat sessions with advisor participation
- Usage tracking: per-account billing and observability

## Data Layer (2026-02-18)
- 8 migrations, 8 models
- Key tables: accounts, users, advisors, councils, council_advisors, conversations, messages, usage_records
- acts_as_tenant ready (models have comments, not yet enabled)
- JSONB columns: settings, preferences, model_config, metadata, configuration, content_blocks, context, custom_prompt_override
- GIN indexes on all JSONB columns
- Polymorphic sender on messages table (sender_type, sender_id)

## Discovered quirks
- 2026-02-10: Initialized `.ai/` template structure and core roles/workflows.
- 2026-02-18: Data layer implemented with scoped multi-tenancy ready for acts_as_tenant gem.
