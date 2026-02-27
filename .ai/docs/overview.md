# App overview

## What this app does

Small Council is a multi-tenant AI advisor platform. Organizations create **Spaces** (contextual containers) that hold **Councils** (groups of AI advisors). Users start **Conversations** within councils, where advisors respond based on configurable **Rules of Engagement** (Round Robin, Moderated, On Demand, Silent, or Consensus).

The platform tracks AI usage per account with encrypted provider credentials, supports multiple LLM providers (OpenAI, Anthropic, GitHub Models), and delivers real-time chat via Turbo Streams.

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
| Tests | Minitest (565 tests, ~48% coverage) |
| Auth | authentication-zero |
| Multi-tenancy | acts_as_tenant (active) |
| AI APIs | ruby-openai, anthropic |

## Business domains

- **Spaces**: Contextual containers (workspaces) holding councils
- **Councils**: Groups of AI advisors that collaborate
- **Advisors**: AI personas with LLM configuration
- **Conversations**: Chat sessions with advisor participation
- **AI Integration**: Multi-provider LLM support with encrypted credentials
- **Usage Tracking**: Per-account billing and observability

## Repo landmarks

```
app/
├── controllers/    # Request handling
├── models/         # 10 models (Account, User, Space, Council, Advisor, etc.)
├── views/          # ERB templates with DaisyUI components
├── services/       # AiClient, ScribeCoordinator
├── jobs/           # GenerateAdvisorResponseJob (Solid Queue)
└── assets/         # Tailwind CSS v4 + DaisyUI

test/               # 565 tests: models, controllers, integration, security, services
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
bin/rails test            # Full suite (455 tests)

# Build
bin/rails assets:precompile # CSS compilation

# Database
bin/rails db:migrate
bin/rails db:reset        # + demo user (demo@example.com / password123)
```

Rules:
- Keep this file to a few paragraphs + bullet lists.
- Prefer concrete commands/paths over vague descriptions.
