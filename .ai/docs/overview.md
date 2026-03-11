# App overview

## What this app does

Small Council is a multi-tenant AI advisor workspace. Accounts own Spaces; Spaces contain Councils and Advisors; Conversations run in a Space as either `council_meeting` or `adhoc`.

Message orchestration is asynchronous and runtime-driven: user messages create advisor placeholders, `AI.runtime_for_conversation(...).user_posted(...)` schedules responses, and `AI.generate_advisor_response` runs through `AI::Runner` (`AIRunnerJob` when async). `AI::Handlers::ConversationResponseHandler` persists completion/error state and continues sequencing. Turbo Streams keep chat updated in real time. A per-space Scribe advisor is auto-created and can run management/memory tools.

AI-assisted form generation is a separate utility flow: `FormFillersController#create` calls `AI.generate_text(..., async: true)`, which runs a `TextTask` and returns results through `AI::Handlers::TurboFormFillerHandler`.

## Tech stack

| Layer | Technology |
|-------|------------|
| Backend | Rails 8.1.2, Ruby 4.0.1 |
| Database | PostgreSQL |
| Frontend | Hotwire/Turbo + Stimulus |
| Styling | Tailwind CSS v4 + DaisyUI v5 |
| Jobs | Solid Queue (`AIRunnerJob`) |
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
- Reusable AI form filling for advisor and council creation/edit flows

## Repo landmarks

```
app/
├── controllers/    # Request handling + authorization/scoping
├── models/         # Tenant-scoped domain models + CurrentAttributes
├── services/       # ProviderConnectionTester, InlineDiff
├── libs/ai/        # Runner, contexts, tasks, handlers, runtimes, trackers, tools
├── jobs/           # AIRunnerJob
├── views/          # ERB + Turbo Streams + DaisyUI classes
└── javascript/     # Stimulus controllers, including form_filler_controller

config/routes.rb    # Auth, spaces/councils/advisors/memories, conversations/messages, providers
test/               # models, controllers, integration, jobs, ai unit/integration, system
.ai/docs/           # Feature + pattern documentation
```

## Common commands

```bash
bundle install
bin/dev
bin/rails server
bin/rails test
bin/rubocop
bin/rails assets:precompile
```
