# Small Council

Multi-tenant AI advisor platform for collaborative conversations.

## Quick Start

```bash
# Install dependencies
bundle install

# Setup database
bin/rails db:create db:migrate db:seed

# Start development server
bin/dev

# Visit http://localhost:3000/sign_in
# Demo credentials: demo@example.com / password123
```

## What It Does

Small Council lets organizations create **Spaces** (workspaces) containing **Councils** (groups of AI advisors). Users start **Conversations** where advisors respond based on configurable **Rules of Engagement**:

- **Round Robin**: Advisors take turns
- **Moderated**: System picks best responder
- **On Demand**: Only @mentioned advisors respond
- **Silent**: User-to-user mode
- **Consensus**: All advisors debate

## Tech Stack

- **Rails 8.1.2** with PostgreSQL
- **Tailwind CSS v4 + DaisyUI v5** for styling
- **Hotwire/Turbo** for real-time updates
- **Solid Queue** for background jobs
- **acts_as_tenant** for multi-tenancy
- **OpenAI/Anthropic/GitHub Models** for AI

## Development Commands

| Command | Purpose |
|---------|---------|
| `bin/dev` | Start web + CSS watch |
| `bin/rails test` | Run test suite (417 tests) |
| `bin/rails db:reset` | Reset DB + demo data |
| `bin/rails tailwindcss:build` | Build CSS once |

## Documentation

- [App Overview](.ai/docs/overview.md) - Architecture and tech stack
- [Features](.ai/docs/features/) - Feature documentation
- [Patterns](.ai/docs/patterns/) - Coding patterns and conventions
- [Memory](.ai/MEMORY.md) - Verified commands and conventions

## Project Structure

```
app/
├── controllers/    # Request handling
├── models/         # 11 models with acts_as_tenant
├── services/       # AI client, coordinator
├── jobs/           # Async response generation
└── views/          # ERB + DaisyUI

test/               # 417 tests, 99.85% coverage
.ai/docs/           # Comprehensive documentation
```

## Configuration

Required environment variables:
- `RAILS_MASTER_KEY` - Production encryption key
- `APP_HOST` - Optional, for host authorization

See `.ai/docs/overview.md` for full details.
