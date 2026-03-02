# Features

This folder documents the app feature-by-feature.

Rules:
- Keep each feature page short.
- Prefer linking to code locations (in the app repo) over large copy/paste.

## Core Platform

- [Authentication](authentication.md) - Sign in, sign up, sessions, password reset
- [Multi-tenancy](multi-tenancy.md) - Account-scoped data isolation via acts_as_tenant
- [UI Framework](ui-framework.md) - Tailwind CSS v4 + DaisyUI styling

## Organization Features

- [Spaces](spaces.md) - Contextual workspaces for organizing councils
- [Councils](councils.md) - Groups of AI advisors that collaborate
- [Advisors](advisors.md) - AI personas with configurable LLM models and tools
- [Council Management Tools](council-management-tools.md) - Scribe-only tools for council and advisor management

## Conversation Features

- [Conversation System](conversation-system.md) - Architecture: RoE, participants, lifecycle
- [Conversations](conversations.md) - UX and API reference: create, post, finish, delete
- [Providers](providers.md) - AI provider credentials and model configuration

## AI Integration

- [AI Integration](ai-integration.md) - AI::Client, ContentGenerator, tool system, usage tracking
- [Model Interactions](model-interactions.md) - Per-message LLM request/response recording and UI

## Data Layer

- [Data Model](data-model.md) - Database schema and model relationships
- [Memory Management](memory-management.md) - Structured memory system with AI-generated summaries
