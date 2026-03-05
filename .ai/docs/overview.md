# App overview

## What this app does

Small Council is a multi-tenant AI advisor workspace. Accounts own Spaces; Spaces contain Councils and Advisors; Conversations run in a Space as either `council_meeting` or `adhoc`.

Message orchestration is asynchronous: user messages create advisor placeholders, `GenerateAdvisorResponseJob` resolves them, and Turbo Streams update chat in real time. A per-space Scribe advisor is auto-created and can run management/memory tools.

## Tech stack

| Layer | Technology |
|-------|------------|
| Backend | Rails 8.1.2, Ruby 4.0.1 |
| Database | PostgreSQL |
| Frontend | Hotwire/Turbo + Stimulus |
| Styling | Tailwind CSS v4 + DaisyUI v5 |
| Jobs | Solid Queue |
| Cache | Solid Cache |
| Cable | Solid Cable |
| Tests | Minitest |
| Auth | authentication-zero generated flows |
| Multi-tenancy | acts_as_tenant + `Current.account` / `Current.space` |
| AI APIs | ruby_llm via `AI::Client` |

## Core domains

- Spaces and councils for organizing advisors and conversations
- Advisor personas with `LlmModel` assignment and canonical handle names
- Conversation lifecycle with RoE (`open`, `consensus`, `brainstorming`)
- Provider/model management for `openai` and `openrouter`
- Memory system with version history and export
- Model interaction recording per AI response (`ModelInteraction`)

## Repo landmarks

```
app/
├── controllers/    # Request handling + authorization/scoping
├── models/         # Tenant-scoped domain models + CurrentAttributes
├── services/       # ConversationLifecycle, CommandParser, ProviderConnectionTester, InlineDiff
├── libs/ai/        # Client, content generator, model manager, tools, adapters, interaction recorder
├── jobs/           # GenerateAdvisorResponseJob, GenerateConversationTitleJob
└── views/          # ERB + Turbo Streams + DaisyUI classes

config/routes.rb    # Auth, spaces/councils/advisors/memories, conversations/messages, providers
test/               # models, controllers, integration, jobs, ai unit/integration, system
.ai/docs/           # Feature + pattern documentation
```

## Common commands

```bash
bin/dev
bin/rails server
bin/rails test
bin/rubocop
bin/rails assets:precompile
```
