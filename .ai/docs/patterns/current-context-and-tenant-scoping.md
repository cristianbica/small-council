# Current Context and Tenant Scoping

Request and job logic must run with explicit tenant and space context.

## Core pattern

1. Set `Current.account` from authenticated user/session.
2. Set `ActsAsTenant.current_tenant = Current.account`.
3. Resolve `Current.space` from `session[:space_id]`, then fallback to first account space.
4. Auto-create default `General` space only when account has no spaces.

This is implemented in `ApplicationController` before actions.

## Model convention

Tenant-bound models declare:

```ruby
acts_as_tenant :account
belongs_to :account
```

Common examples: `Conversation`, `Message`, `Advisor`, `Provider`, `LlmModel`, `Memory`.

## Controller convention

Use `Current.space.<association>` and `Current.account.<association>` for lookups, not global model queries.

Examples:
- `Current.space.conversations.find(params[:id])`
- `Current.account.providers.find(params[:id])`

## Background jobs

Async execution should carry serializable context and rehydrate tenant-scoped context before model operations.

`AI::Runner` does this by resolving typed context objects (`AI::Contexts::*`) from job payloads.

## Test convention

- Model/unit tests: call `set_tenant(account)` before creating tenant-scoped records.
- Request/integration tests: establish session/user and host context so `Current.account` and `Current.space` are deterministic.

## Guardrails

- Never trust raw ids without scoping through `Current.account`/`Current.space`.
- Treat space switching as session state that can be stale; always re-lookup through account scope.
