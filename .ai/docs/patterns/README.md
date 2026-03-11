# Patterns

This folder documents reusable coding patterns and conventions.

Rules:
- Keep pattern pages short.
- Prefer a few canonical patterns over many near-duplicates.

## Core Patterns

- [Architecture](architecture.md) - App structure and responsibilities
- [Current Context and Tenant Scoping](current-context-and-tenant-scoping.md) - `Current.*` + `acts_as_tenant` request/job boundaries
- [Testing](testing.md) - Test philosophy, setup, and mock patterns
- [i18n](i18n.md) - Internationalization patterns
- [UI Components](ui-components.md) - Reusable UI patterns and form validation
- [Command Pattern](command-pattern.md) - Legacy command classes and migration notes

## Infrastructure Patterns

- [Background Jobs](background-jobs.md) - Solid Queue with multi-tenancy
- [Turbo Streams](turbo-streams.md) - Real-time UI updates
- [Custom RB Config](custom-rb-config.md) - Rails configuration override pattern
- [Tool System](tool-system.md) - AI::Tools::AbstractTool registry for AI agent actions
- [Agents](agents.md) - Agent classes, task bindings, and tool policy defaults
- [Prompts](prompts.md) - ERB prompt resolution, naming, and runtime usage
- [Tasks](tasks.md) - AI::Runner task lifecycle and handler/tracker flow

## Security Patterns

- [Security Testing](security-testing.md) - Security test patterns for tenant isolation, authorization
