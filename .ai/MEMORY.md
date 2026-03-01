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

## Test conventions
- Always add advisors as conversation_participants, not just to council.advisors
- RoE types: `open`, `consensus`, `brainstorming` (legacy: round_robin, silent, on_demand removed)
- Context builders require space - either directly or via conversation.council.space
- Invite command normalizes: `@mention` → removes `@` → replaces `_` with ` ` for lookup
- Conversations require at least one non-scribe advisor for updates (validation on :update)
- Messages: `depth` is calculated method, not a column
- `pending_advisor_ids` is JSONB array; `solved?` checks empty/nil
- `command?` detects leading `/`, `command_name` extracts first word after /
- Tests for acts_as_tenant models should use `set_tenant(account)` in setup

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
- Spaces: contextual workspaces containing councils (each auto-creates a Scribe advisor)
- Councils: groups of AI advisors that collaborate
- Conversations: chat sessions (`council_meeting` or `adhoc`) with RoE (open/consensus/brainstorming)
- Advisors: AI personas with configurable LLM models and tool access; `is_scribe` flag for Scribe
- Tool System: 13 tools in `app/libs/ai/tools/` using `AI::Tools::BaseTool`
- Usage tracking: per-account billing via `UsageRecord` (auto-created by `AI::Client#chat`)
- Model interactions: per-message LLM call recording via `ModelInteraction` (`AI::ModelInteractionRecorder` using RubyLLM event handlers; closure-based context in `AI::Client#chat`; records both "chat" and "tool" interaction types)
- AI Providers: OpenAI, OpenRouter with encrypted API credentials
- LlmModels: Per-account model configuration; `account.default_llm_model` fallback
- Memories: 4 types (summary auto-fed to AI; others query-on-demand via tools)

## Data Layer (2026-02-27)
- 13 migrations, 13 models (added Memory, MemoryVersion, ModelInteraction)
- Key tables: accounts, users, spaces, advisors, councils, council_advisors, conversations, messages, usage_records, providers, llm_models, memories, model_interactions
- acts_as_tenant gem is enabled and active (automatic tenant scoping on all queries)
- JSONB columns: settings, preferences, model_config, metadata, configuration, content_blocks, context, custom_prompt_override, credentials
- GIN indexes on all JSONB columns
- Polymorphic sender on messages table (sender_type, sender_id)
- Encrypted credentials: `Provider.credentials` uses Rails encrypted attributes for API keys
- Current attributes: `Current.session`, `Current.user`, `Current.account`, `Current.space`
- Message statuses: `pending`, `complete`, `error`, `cancelled`

## Discovered quirks
- 2026-02-18: Active Record encryption uses deterministic test keys in test environment.
- 2026-02-18: Security test audit - 37+ security tests covering tenant isolation, parameter tampering, mass assignment. See `.ai/docs/patterns/security-testing.md`.
- 2026-02-24: Created `dhh-coder` overlay (coding style) and `dhh-reviewer` overlay (code review persona) for 37signals/DHH Rails conventions
- 2026-02-25: Fixed conversation summary parsing — `extract_section` in `GenerateConversationSummaryJob` supports multiple header formats (`## Key Decisions`, `**Key Decisions:**`, `Key Decisions:`).
- 2026-02-26: Fixed `by_type` scope in Memory model — blank type returns `all`, not `where(memory_type: nil)`.
- 2026-02-27: **Tool System** — 13 tools in `app/libs/ai/tools/` using `AI::Tools::BaseTool` (not old `AdvisorTool`/`ScribeTool`).
- 2026-02-27: **ask_advisor** — Posts in same conversation; creates mention + pending placeholder + enqueues job.
- 2026-02-27: **Delete conversation** — Only conversation starter or council creator can delete.
- 2026-02-28: **AI::Client instance-based** — `AI::Client.new(model:, tools:, system_prompt:).chat(messages:, context:)`. Mock: `AI::Client.stubs(:new).returns(mock_client)`.
- 2026-02-28: **Providers** — OpenAI and OpenRouter only (Anthropic removed). `ruby_llm` 1.12.1 is the unified LLM client.

## Gems
- `ruby_llm` (~> 1.3, locked at 1.12.1) - Unified LLM client (OpenAI + OpenRouter)
- `acts_as_tenant` (~> 1.0) - Multi-tenancy (automatic account scoping)
- `mocha` - Test mocking (stubs/expects in unit/integration tests)
- `simplecov` - Code coverage (test group; configured in test_helper.rb)
- `faraday` (~> 2.0) + `faraday-follow_redirects` - HTTP client (browse_web tool)
- `diffy` (~> 3.4) - Diff library (used by InlineDiff service for memory versions)
- `commonmarker` (~> 2.0) - GitHub Flavored Markdown rendering (MarkdownHelper)
- `AI::ModelInteractionRecorder` — event-handler-based recorder wired into `AI::Client#build_ruby_llm_chat` via `on_end_message`, `on_tool_call`, `on_tool_result`; records chat and tool interactions to `ModelInteraction` table

## UI Framework (2026-02-18)
- Tailwind CSS v4.1.18 via `tailwindcss-rails` gem (no Node.js)
- DaisyUI v5.5.18 for component classes (downloaded as .mjs plugin)
- **Typography styles**: Custom prose styles added in `application.css` for markdown rendering (h1-h3, lists, code blocks, links, etc.)
- Config: `app/assets/tailwind/application.css`
- Output: `app/assets/builds/tailwind.css`
- Theme: `data-theme="light"` on html tag
- Key DaisyUI classes: btn, card, navbar, alert, form-control, input, menu

## UI/UX Standards (2026-02-19)
- Forms use consistent DaisyUI patterns with field-level validation
- Required fields marked with red asterisk (*)
- Error states use `input-error` class + inline error messages
- Empty states use shared `shared/empty_state` partial
- Navigation has active state indicators
- All cards use `bg-base-100 shadow` for consistency
- Primary actions use `btn btn-primary`
- Secondary actions use `btn btn-ghost`
- Cards and list items are clickable with `link_to` wrapper
- Breadcrumbs on all nested pages using DaisyUI `breadcrumbs` class
- Hover effects: `hover:shadow-lg` for cards, `hover:bg-base-300` for list items
- Message copy button appears on hover using `group-hover:opacity-100`

## Provider Integration Wizard (2026-02-19)
- 4-step wizard for adding AI providers: Select → Authenticate → Test → Configure
- Uses `ProviderConnectionTester` service to validate API keys before saving
- Real-time connection testing via AJAX with loading/success/error states
- Session-based state management for multi-step flow
- Supports OpenAI and OpenRouter (provider_type enum: openai, openrouter)
- Provider-specific authentication fields (API Key, optional Organization ID)
- Wizard URL: `/providers/wizard`

## Model Management UI (2026-02-20)
- Browse and enable/disable AI models per provider
- Provider cards show enabled model count with quick access to model management
- Model list shows capabilities (chat, vision, functions) with toggle switches
- Uses `AI::ModelManager` service to sync model metadata from ruby_llm
- Stores model capabilities, pricing, context window in JSONB metadata column
- URLs: `/providers/:id/models` (per-provider), `/providers/models` (all models)

## Memory Management System (2026-02-26)
- New `memories` table with 4 memory types: summary, conversation_summary, conversation_notes, knowledge
- ONLY `summary` type is auto-fed to AI agents; others require query_memories tool
- Memory CRUD at `/spaces/:space_id/memories` with export (Markdown/JSON)
- Available tools: finish_conversation, create_memory, query_memories
- Data migration: Existing space.memory migrated to summary-type memories
- Docs: `.ai/docs/features/memory-management.md`

## Scribe Tool Capabilities (2026-02-27, updated 2026-02-28)
The Scribe/Advisors have access to tools via `app/libs/ai/tools/` (`AI::Tools::BaseTool`):

**Conversation tools:** finish_conversation, ask_advisor, summarize_conversation
**External tools:** browse_web
**Internal tools:** create_memory, list_memories, query_memories, read_memory, update_memory, list_conversations, query_conversations, read_conversation, get_conversation_summary

- Tools are defined in `app/libs/ai/tools/` using `AI::Tools::BaseTool`
- Context is passed via tool context object (conversation, space, advisor, user)

## AI Architecture (2026-02-28, verified 2026-02-28)
- `AI::Client` is **instance-based**: `AI::Client.new(model:, tools: [], system_prompt:, temperature:)` then `.chat(messages:, context: {})`.
- Class methods on `AI::Client`: `AI::Client.test_connection(provider:)` and `AI::Client.list_models(provider:)` — used by `ProviderConnectionTester` and `AI::ModelManager`.
- `AI::Client#chat` returns `AI::Model::Response` (content, tool_calls, usage).
- `AI::Client` auto-tracks usage via `UsageRecord.create!` inside `#track_usage`; no double-tracking.
- `Provider.provider_type` enum: `openai`, `openrouter` only (no anthropic).
- `Current.user` has no setter — to stub current user: `Current.session = stub(user: some_user)`.
- `Space#create_scribe_advisor` rescues failures and returns nil; always ensure account has an LLM model before calling `scribe_advisor` or creating a Space in tests.
- Tool system lives in `app/libs/ai/tools/` with `AI::Tools::BaseTool`; adapter at `app/libs/ai/adapters/ruby_llm_tool_adapter.rb`.
- Deleted stale classes (2026-02-28): ScribeTool, AdvisorTool, ToolExecutionContext, MemorySearch, ScribeToolExecutor.
- Mock pattern: `AI::Client.stubs(:new).returns(mock_client)` + `mock_client.stubs(:chat).returns(mock_response)`.
- **RubyLLM::Message API**: uses `model_id` (NOT `model`). Available methods: `content`, `input_tokens`, `output_tokens`, `model_id`, `tool_calls`, `tool_call?`, `role`, `thinking`.
- Test coverage (2026-03-01, verified): 1420 runs, 96.83% line, 85.79% branch.
- 2026-03-01: **Conversation finishing is Scribe-only** — no UI routes for finish/cancel_pending/approve_summary/reject_summary/regenerate_summary. Scribe follow-ups gated to `council_meeting` + `active` only.

## Additional Services (2026-02-28)
- `AI::ContentGenerator` — instance-based, intent-driven: `AI::ContentGenerator.new.generate_advisor_response(advisor:, conversation:, ...)`.
- `InlineDiff` — module in `app/services/inline_diff.rb` for word-level diff display (used by memory versions).
- `MarkdownHelper` — in `app/helpers/markdown_helper.rb`, uses `commonmarker` gem for GFM rendering.
- `GenerateConversationSummaryJob` — async job that generates conversation summary on conclusion.

## Ruby Version (2026-02-19)
- **Ruby 4.0.1** (upgraded from 3.4.8) - Uses mise for version management
- Bundler 4.0.3 with RubyGems 4.0.3
- Note: Minor Bundler/RubyGems platform warnings are expected and harmless

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
