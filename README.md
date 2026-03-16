# Small Council

Small Council is a multi-tenant Rails app for running collaborative AI conversations inside shared workspaces. Accounts own spaces, spaces contain councils and advisors, and users can run either council meetings or ad hoc advisor threads with different Rules of Engagement.

This repository is the application itself: a Rails 8 app with Hotwire, PostgreSQL, account scoping, asynchronous AI response orchestration, provider management, and seeded demo data for local development.

## Project Status

Small Council is an experiment. The repository was written entirely by AI using [Orchestra](https://github.com/cristianbica/orchestra), with heavy supervision, review, and direction from the repository owner.

As with many experimental projects, the codebase may contain bugs, security issues, or other defects. Evaluate it carefully before using it in any environment, and use it at your own risk.

## Product Overview

Small Council organizes AI collaboration around a few core concepts:

- **Spaces** group work for an account.
- **Councils** group advisors for repeated collaboration.
- **Advisors** are persona-style participants backed by configured LLM models.
- **Conversations** can be either council meetings or ad hoc threads.
- **Memories** support stored context with version history and export.

## Key Features

- Multi-tenant account and space model using `acts_as_tenant`.
- Collaborative advisor conversations with async AI response generation.
- Three current Rules of Engagement modes: `open`, `consensus`, and `brainstorming`.
- Provider and model management for OpenAI and OpenRouter.
- Real-time chat updates through Hotwire and Turbo Streams.
- Per-space memory management with version history and export.
- AI-assisted form filling flow for advisor and council creation/editing.

## Rules of Engagement

The repository currently supports these conversation modes:

| Mode | Behavior |
| --- | --- |
| `open` | Only mentioned advisors respond; `@all` can be used as a broad invite. |
| `consensus` | Advisors participate in a group discussion aimed at reaching consensus. |
| `brainstorming` | Advisors collaborate in short idea-generation rounds. |

## Supported AI Providers

- OpenAI
- OpenRouter

## Prerequisites

- Ruby `4.0.1`
- Bundler
- PostgreSQL

Optional for production/container workflows:

- Docker

## Setup

### Quick start

```bash
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/dev
```

Then open `http://localhost:3000/sign_in`.

### One-command setup

`bin/setup` will:

- install gems if needed
- run `bin/rails db:prepare`
- clear logs and temp files
- start `bin/dev` unless you pass `--skip-server`

## Running Locally

`bin/dev` starts the Rails server plus the Tailwind watcher defined in `Procfile.dev`.

If you prefer to run pieces separately:

```bash
bin/rails server
bin/rails tailwindcss:watch
```

Sign-in and sign-up routes are available at:

- `http://localhost:3000/sign_in`
- `http://localhost:3000/sign_up`

## Demo Login

If you have run `bin/rails db:seed`, the repository seeds a demo account:

- Email: `demo@example.com`
- Password: `password123`

## Verified Development Commands

These command results are documented in `.ai/MEMORY.md` and were already verified in this repository:

| Command | Result | Notes |
| --- | --- | --- |
| `bundle check` | pass | Dependencies already satisfied when verified. |
| `bundle install` | pass | Gem installation path verified. |
| `bin/rails test` | pass | `1195 runs, 0 failures, 0 errors, 3 skips`. |
| `bin/rubocop` | fail | One existing trailing-comma offense was recorded in `app/models/conversation.rb`. |
| `bin/rails assets:precompile` | pass | Tailwind/DaisyUI emits a known `@property` warning during the verified run. |

## Architecture and Tech Stack

- Rails `8.1.2`
- Ruby `4.0.1`
- PostgreSQL
- Hotwire: Turbo + Stimulus
- Tailwind CSS v4 + DaisyUI v5
- Solid Queue, Solid Cache, and Solid Cable
- `ruby_llm` through the app's `AI::Client`
- `acts_as_tenant` for account scoping
- Minitest for automated tests

At a high level, user messages are persisted first, then AI response work is scheduled asynchronously through the app's AI runtime and runner path. Turbo Streams keep conversation views updated as advisor responses complete.

## Configuration Notes

- Development and test use PostgreSQL databases configured in [config/database.yml](config/database.yml).
- Development and test default to PostgreSQL on `127.0.0.1` with username `postgres` unless overridden.
- `RAILS_MASTER_KEY` is required in production for encrypted credentials.
- `APP_HOST` is optional in development and test for host authorization and default URL options.
- Provider API keys are managed through the app and stored encrypted at rest.

## Project Structure

```text
app/
	controllers/    Request handling, auth, and scoped UI flows
	models/         Tenant-scoped domain models and state
	libs/ai/        AI runtimes, handlers, tasks, prompts, and tools
	jobs/           Background job entrypoints such as AIRunnerJob
	views/          ERB views and Turbo Stream templates
	javascript/     Stimulus controllers and browser-side behavior

config/           Rails configuration, routes, environments
db/               Schema, migrations, and seeds
test/             Unit, integration, job, AI, and system tests
.ai/docs/         Maintainer-oriented architecture and feature docs
```

## Contributing

Contributions are welcome. Because the project is also an ongoing experiment in AI-assisted software development, contributions should ideally follow the same direction and be produced with AI-assisted workflows, with appropriate human review before submission.
