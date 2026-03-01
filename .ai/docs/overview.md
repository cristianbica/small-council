# App overview

## What this app does

Small Council is a multi-tenant AI advisor platform. Organizations create **Spaces** (contextual containers) that hold **Councils** (groups of AI advisors). Users start **Conversations** within councils, where advisors respond based on configurable **Rules of Engagement** (Open, Consensus, Brainstorming). A special **Scribe** advisor moderates each space and facilitates conversation flow.

The platform tracks AI usage per account with encrypted provider credentials, supports multiple LLM providers (OpenAI, OpenRouter), and delivers real-time chat via Turbo Streams.

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
| Tests | Minitest (~1396 runs, 96.79% line / 85.38% branch coverage) |
| Auth | authentication-zero |
| Multi-tenancy | acts_as_tenant (active) |
| AI APIs | ruby_llm |

## Business domains

- **Spaces**: Contextual containers (workspaces) holding councils; each has a Scribe advisor
- **Councils**: Groups of AI advisors that collaborate
- **Advisors**: AI personas with LLM configuration (via LlmModel)
- **Conversations**: Chat sessions (`council_meeting` or `adhoc`) with advisor participation
- **AI Integration**: Multi-provider LLM support via `AI::Client` (class methods)
- **Usage Tracking**: Per-account billing and observability
- **Memories**: Persistent knowledge entries with versioning

## Repo landmarks

```
app/
├── controllers/    # Request handling
├── models/         # 17 models: Account, User, Space, Council, Advisor,
│                   #   CouncilAdvisor, Conversation, ConversationParticipant,
│                   #   Message, Memory, MemoryVersion, Provider, LlmModel,
│                   #   UsageRecord, Session, Current, ApplicationRecord
├── views/          # ERB templates with DaisyUI components
├── services/       # ConversationLifecycle, ProviderConnectionTester, InlineDiff, CommandParser
├── libs/ai/        # AI::Client (instance), AI::ContentGenerator, AI::ModelManager,
│                   #   AI::ContextBuilders, AI::Tools (13 tools), AI::Model (Response/TokenUsage)
├── jobs/           # GenerateAdvisorResponseJob, GenerateConversationSummaryJob (Solid Queue)
└── assets/         # Tailwind CSS v4 + DaisyUI

test/               # ~1396 runs: models, controllers, integration, jobs, ai/unit, ai/integration
config/
├── routes.rb       # All app routes
└── initializers/   # App configuration
.ai/docs/           # This documentation
```

## Verified commands

```bash
# Development
bin/dev                    # Start web + CSS watch
bin/rails server          # Rails only

# Testing
bin/rails test            # Full suite

# Build
bin/rails assets:precompile  # CSS compilation

# Database
bin/rails db:migrate
bin/rails db:reset        # + demo user (demo@example.com / password123)
```

Rules:
- Keep this file to a few paragraphs + bullet lists.
- Prefer concrete commands/paths over vague descriptions.
