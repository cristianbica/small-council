# Architecture

Multi-tenant Rails architecture with clear separation of concerns.

## Layer Responsibilities

```
┌─────────────────────────────────────────────────────────┐
│  Controllers (app/controllers/)                         │
│  - Handle HTTP requests                                 │
│  - Validate parameters                                  │
│  - Enforce authorization                                │
│  - Delegate to services/models                          │
├─────────────────────────────────────────────────────────┤
│  Services (app/services/)                                 │
│  - Orchestrate complex operations                       │
│  - ProviderConnectionTester, InlineDiff                  │
├─────────────────────────────────────────────────────────┤
│  AI Lib (app/libs/ai/)                                  │
│  - AI::Runner (task/context/handler/tracker execution)  │
│  - AI::Contexts / AI::Tasks / AI::Handlers              │
│  - AI::Runtimes::*ConversationRuntime (RoE sequencing)  │
│  - AI::Trackers (usage + model-interaction persistence) │
│  - AI::Client + AI::Client::Chat (transport/session)    │
│  - AI::Tools::AbstractTool + registry-based inventory   │
├─────────────────────────────────────────────────────────┤
│  Models (app/models/)                                   │
│  - Data integrity and validation                        │
│  - Domain logic for that entity                         │
│  - Relationships and scopes                             │
├─────────────────────────────────────────────────────────┤
│  Jobs (app/jobs/)                                       │
│  - Async processing                                     │
│  - Always set tenant context                            │
│  - Idempotent design                                     │
├─────────────────────────────────────────────────────────┤
│  Views (app/views/)                                    │
│  - Presentation only                                     │
│  - DaisyUI component classes                           │
│  - Turbo Frame/Stream integration                      │
└─────────────────────────────────────────────────────────┘
```

## Multi-Tenancy Architecture

### Automatic Query Scoping
```ruby
# acts_as_tenant handles scoping automatically
Current.account = user.account
Advisor.all  # => SELECT * FROM advisors WHERE account_id = X
```

### Current Attributes Pattern
```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user_agent, :ip_address
  attribute :account, :space  # tenant context
  delegate :user, to: :session, allow_nil: true
end
```

### Tenant Context Flow
```
Request
  ↓
ApplicationController#set_current_tenant
  ↓
Current.account = Current.user.account
  ↓
All queries automatically scoped
```

## Service Objects

Used for complex orchestration:

- `AI::Runner` - Rehydrates and executes task/context/handler/tracker graphs
- `AI::Runtimes::*ConversationRuntime` - RoE-specific advisor sequencing
- `ProviderConnectionTester` - Validates API credentials before saving
- `InlineDiff` - Word-level diff display for memory versions

Pattern:
```ruby
class ServiceName
  def initialize(dependencies)
    @deps = dependencies
  end

  def perform
    # orchestration logic
  end
end
```

## Design Principles

1. **Thin controllers** - Controllers handle HTTP, delegate logic
2. **Rich models** - Business logic lives in models
3. **Service objects for orchestration** - Complex multi-model operations
4. **Jobs for async work** - All external API calls, heavy processing
5. **Tenant context everywhere** - Background jobs must set tenant explicitly

## Conventions

- Document new patterns in `.ai/docs/patterns/`
- Keep classes small (< 100 lines ideal)
- One public method per service object
- Jobs are idempotent and retry-safe
