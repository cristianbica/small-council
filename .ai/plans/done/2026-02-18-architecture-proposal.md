# Architecture Proposal: Small Council (SC) - Rails 8 AI SaaS

**Date:** 2026-02-18  
**Status:** Draft - Pending Approval

---

## Executive Summary

- **Multi-provider LLM architecture** using `ruby_llm` gem for unified OpenAI, Anthropic, Gemini support with provider-swappable adapters
- **Scoped multi-tenancy** (not RLS) via `tenant_id` columns with ActsAsTenant for simpler ops and Rails-native patterns
- **Rails 8 native authentication** generator with `authentication-zero` as fallback for advanced features (2FA, OAuth)
- **Service-oriented business layer** using plain Ruby service objects + Solid Queue for async AI processing
- **JSONB-heavy schema** for flexible AI configurations with GIN indexes for query performance

---

## Goal

Design a comprehensive, production-ready architecture for Small Council—a Rails 8 SaaS enabling users to create AI councils (groups of AI advisors) for collaborative decision-making.

## Non-goals

- Real-time collaborative editing (like Google Docs) - out of scope for MVP
- Mobile native apps - web-first, PWA later if needed
- Custom AI model training/fine-tuning
- Voice/video input processing (text-first)

## Scope + Assumptions

- Fresh Rails 8 app with PostgreSQL, Propshaft, Solid Queue/Cache/Cable
- Target: SaaS with multi-user accounts, councils, AI advisors, conversations
- Users pay for AI usage (metered) + subscription tiers
- Hotwire/Turbo for reactive UI, no SPA framework
- Self-hosted (Kamal), not serverless

---

## 1. Data Layer - Database Schema Design

### 1.1 Core Entity Relationships

```
Account (tenant)
├── Users (many)
├── Councils (many)
│   ├── Advisors (many-to-many via council_advisors)
│   └── Conversations (many)
│       └── Messages (many, polymorphic: user/ai)
├── Advisors (many - custom configs)
├── Billing::Subscription
└── Usage::Credits
```

### 1.2 Schema Design (PostgreSQL)

**MVP Tables:**

```ruby
# accounts - Multi-tenancy root
create_table :accounts do |t|
  t.string :name, null: false
  t.string :slug, null: false, index: { unique: true }
  t.string :stripe_customer_id
  t.jsonb :settings, default: {}
  t.datetime :trial_ends_at
  t.timestamps
end
add_index :accounts, :settings, using: :gin

# users - Scoped to account
create_table :users do |t|
  t.references :account, null: false, foreign_key: true
  t.string :email, null: false
  t.string :password_digest
  t.string :role, default: 'member' # admin, member
  t.jsonb :preferences, default: {}
  t.timestamps
end
add_index :users, [:account_id, :email], unique: true

# councils - Core entity
create_table :councils do |t|
  t.references :account, null: false, foreign_key: true
  t.references :user, null: false, foreign_key: true # creator
  t.string :name, null: false
  t.text :description
  t.string :visibility, default: 'private' # private, shared
  t.jsonb :configuration, default: {} # voting rules, consensus threshold
  t.timestamps
end
add_index :councils, [:account_id, :name]
add_index :councils, :configuration, using: :gin

# advisors - AI persona configurations
create_table :advisors do |t|
  t.references :account, null: false, foreign_key: true
  t.string :name, null: false
  t.text :system_prompt, null: false
  t.string :model_provider, null: false # openai, anthropic, gemini
  t.string :model_id, null: false # gpt-4o, claude-3-5-sonnet, etc.
  t.jsonb :model_config, default: {} # temperature, max_tokens, etc.
  t.jsonb :metadata, default: {} # persona traits, expertise areas
  t.boolean :global, default: false # shared across accounts
  t.timestamps
end
add_index :advisors, :model_config, using: :gin
add_index :advisors, :metadata, using: :gin

# council_advisors - join table
create_table :council_advisors do |t|
  t.references :council, null: false, foreign_key: true
  t.references :advisor, null: false, foreign_key: true
  t.integer :position, default: 0
  t.jsonb :custom_prompt_override, default: {}
  t.timestamps
end
add_index :council_advisors, [:council_id, :advisor_id], unique: true

# conversations
create_table :conversations do |t|
  t.references :account, null: false, foreign_key: true
  t.references :council, null: false, foreign_key: true
  t.references :user, null: false, foreign_key: true
  t.string :title
  t.string :status, default: 'active' # active, archived
  t.jsonb :context, default: {} # decision context, constraints
  t.datetime :last_message_at
  t.timestamps
end
add_index :conversations, [:account_id, :last_message_at]
add_index :conversations, :context, using: :gin

# messages - polymorphic content
create_table :messages do |t|
  t.references :account, null: false, foreign_key: true
  t.references :conversation, null: false, foreign_key: true
  t.references :sender, polymorphic: true, null: false # User or Advisor
  t.string :role, null: false # user, advisor, system
  t.text :content
  t.jsonb :content_blocks, default: [] # structured content (text, reasoning, votes)
  t.jsonb :metadata, default: {} # tokens used, latency, model info
  t.string :status, default: 'complete' # pending, complete, error
  t.timestamps
end
add_index :messages, [:conversation_id, :created_at]
add_index :messages, :metadata, using: :gin

# usage_records - Metering for billing
create_table :usage_records do |t|
  t.references :account, null: false, foreign_key: true
  t.references :message, null: true, foreign_key: true
  t.string :provider, null: false
  t.string :model, null: false
  t.integer :input_tokens, default: 0
  t.integer :output_tokens, default: 0
  t.integer :cost_cents, default: 0 # calculated or actual
  t.datetime :recorded_at
end
add_index :usage_records, [:account_id, :recorded_at]
```

### 1.3 Multi-Tenancy Approach: Scoped Queries (Recommended)

**Decision:** Use `tenant_id` scoped queries via `acts_as_tenant` gem, NOT PostgreSQL RLS.

**Rationale:**
| Approach | Pros | Cons |
|----------|------|------|
| **Scoped Queries** | Simple, Rails-native, easy to debug, works with all gems | Requires discipline (use `ActsAsTenant.current_tenant =`) |
| **RLS** | Database-enforced, impossible to bypass | Complex with connection pooling, harder to debug, performance overhead, complicates migrations |

**Implementation:**
```ruby
# config/initializers/acts_as_tenant.rb
ActsAsTenant.configure do |config|
  config.require_tenant = true # Raise if no tenant set
end

# app/controllers/concerns/set_current_account.rb
class ApplicationController < ActionController::Base
  set_current_tenant_through_filter
  before_action :set_current_account

  private

  def set_current_account
    current_account = current_user&.account
    ActsAsTenant.current_tenant = current_account
  end
end

# All models scoped to account
class Council < ApplicationRecord
  acts_as_tenant :account
  # ...
end
```

### 1.4 JSONB Strategy & Indexing

**JSONB columns used for:**
- Flexible AI configurations (models, providers change frequently)
- Advisor persona metadata (traits, expertise)
- Message content blocks (text, reasoning, structured output)
- Usage metadata (token counts, latency)

**Indexing Strategy:**
```ruby
# GIN indexes for JSONB queries
add_index :advisors, :model_config, using: :gin
add_index :advisors, :metadata, using: :gin, opclass: :jsonb_path_ops

# Composite indexes for common queries
add_index :messages, [:conversation_id, :created_at]
add_index :councils, [:account_id, :updated_at]
```

**Trade-offs:**
- Use `jsonb_path_ops` for existence queries (`@>`)
- Use default GIN for key access (`->`)
- Avoid JSONB for columns needing frequent updates (use normalized columns)

---

## 2. Integration Layer - AI Service Integration

### 2.1 LLM Provider Abstraction

**Decision:** Use `ruby_llm` gem (universal adapter) with custom wrapper for streaming/processing.

**Architecture:**
```
app/services/llm/
├── client.rb              # Factory/provider selector
├── providers/
│   ├── base.rb            # Abstract interface
│   ├── ruby_llm_adapter.rb # Concrete implementation
│   └── mock_adapter.rb    # Testing
├── streaming/
│   ├── response_handler.rb
│   └── turbo_broadcaster.rb
└── errors.rb              # Custom error hierarchy
```

**Rationale for ruby_llm vs alternatives:**
| Gem | Best For | Notes |
|-----|----------|-------|
| **ruby_llm** | Multi-provider, Rails integration | `acts_as_chat`, unified interface, 800+ models, streaming support |
| langchainrb | Complex agent workflows, RAG | Overkill for simple chat, adds complexity |
| ruby-openai | OpenAI only | Vendor lock-in, requires wrappers for multi-provider |

**Implementation Pattern:**
```ruby
# app/services/llm/client.rb
module Llm
  class Client
    def initialize(provider: nil, model: nil)
      @provider = provider || default_provider
      @model = model || default_model(@provider)
    end

    def chat(messages:, tools: nil, &block)
      adapter.chat(
        model: @model,
        messages: format_messages(messages),
        tools: tools,
        &block
      )
    end

    def stream_chat(messages:, &block)
      adapter.chat(
        model: @model,
        messages: format_messages(messages),
        stream: true,
        &block
      )
    end

    private

    def adapter
      @adapter ||= Llm::Providers::RubyLlmAdapter.new(@provider)
    end

    def format_messages(messages)
      messages.map do |m|
        { role: m.role, content: m.content }
      end
    end
  end
end

# app/services/llm/providers/ruby_llm_adapter.rb
module Llm
  module Providers
    class RubyLlmAdapter < Base
      def initialize(provider)
        @client = RubyLLM.new(provider: provider)
      end

      def chat(model:, messages:, tools: nil, stream: false, &block)
        chat_obj = @client.chat(model: model)
        
        messages.each { |m| chat_obj.add_message(role: m[:role], content: m[:content]) }
        
        if stream && block_given?
          chat_obj.stream(&block)
        else
          chat_obj.complete
        end
      end

      def models
        RubyLLM.models.by_provider(@provider)
      end
    end
  end
end
```

### 2.2 Streaming Responses with Hotwire

```ruby
# app/jobs/generate_advisor_response_job.rb
class GenerateAdvisorResponseJob < ApplicationJob
  queue_as :llm_requests
  limits_concurrency to: 3, key: ->(account_id) { account_id }, duration: 2.minutes

  def perform(conversation_id, advisor_id, prompt)
    conversation = Conversation.find(conversation_id)
    advisor = Advisor.find(advisor_id)
    account = conversation.account

    message = conversation.messages.create!(
      sender: advisor,
      role: 'advisor',
      status: 'pending',
      content: ''
    )

    stream_to_turbo(message)

    content_buffer = ""
    metadata = {}

    Llm::Client.new(
      provider: advisor.model_provider,
      model: advisor.model_id
    ).stream_chat(
      messages: build_context(conversation, advisor, prompt)
    ) do |chunk|
      content_buffer += chunk.content
      message.update_column(:content, content_buffer)
      
      # Turbo Stream to update UI
      Turbo::StreamsChannel.broadcast_replace_to(
        "conversation_#{conversation_id}",
        target: "message_#{message.id}",
        partial: "messages/message",
        locals: { message: message }
      )
    end

    message.update!(
      status: 'complete',
      metadata: metadata.merge(tokens_used: estimate_tokens(content_buffer))
    )

    record_usage(account, message, metadata)
  rescue => e
    message&.update!(status: 'error', metadata: { error: e.message })
    raise
  end

  private

  def build_context(conversation, advisor, prompt)
    # Build conversation history + system prompt
    [
      { role: 'system', content: advisor.system_prompt },
      *conversation.messages.map { |m| { role: m.role, content: m.content } },
      { role: 'user', content: prompt }
    ]
  end
end
```

### 2.3 Rate Limiting & Retry Strategy

```ruby
# app/services/llm/rate_limiter.rb
module Llm
  class RateLimiter
    LIMITS = {
      openai: { rpm: 500, tpm: 150_000 },
      anthropic: { rpm: 1000, tpm: 80_000 }
    }.freeze

    def initialize(provider, account)
      @provider = provider
      @account = account
    end

    def throttle!
      key = "rate_limit:#{@provider}:#{@account.id}"
      
      current = SolidCache.read(key) || { count: 0, window_start: Time.current }
      
      if current[:window_start] < 1.minute.ago
        current = { count: 0, window_start: Time.current }
      end

      current[:count] += 1
      
      if current[:count] > LIMITS.dig(@provider, :rpm)
        raise Llm::RateLimitExceeded, "Rate limit exceeded for #{@provider}"
      end

      SolidCache.write(key, current, expires_in: 2.minutes)
    end
  end
end

# app/jobs/concerns/llm_retryable.rb
module LlmRetryable
  extend ActiveSupport::Concern

  included do
    retry_on Llm::RateLimitExceeded, wait: :polynomially_longer, attempts: 5
    retry_on Llm::ProviderError, wait: 5.seconds, attempts: 3
    discard_on Llm::InvalidRequestError
  end
end
```

---

## 3. Libraries & Gems

### 3.1 Core AI/LLM Integration

| Gem | Purpose | When to Use |
|-----|---------|-------------|
| **ruby_llm** (~> 1.0) | Multi-provider LLM client | Primary choice - unified API for OpenAI, Anthropic, Gemini |
| anthropic (~> 0.3) | Direct Anthropic SDK | Fallback if ruby_llm lacks specific features |
| ruby-openai (~> 7.0) | Direct OpenAI SDK | Fallback if needed |

**Rationale:** `ruby_llm` provides:
- Single interface for 10+ providers
- `acts_as_chat` Rails integration
- 800+ model registry with pricing
- Streaming + tool support
- Only 3 dependencies (Faraday, Zeitwerk, Marcel)

### 3.2 Authentication & Authorization

**Decision Matrix:**

| Solution | Best For | Notes |
|----------|----------|-------|
| **Rails 8 Auth Generator** | MVP, simple needs | Built-in, no deps, basic login/logout/password reset |
| **authentication-zero** | Production SaaS | Generated code (not gem), 2FA, OAuth, passwordless, audit logging |
| Devise | Rapid prototyping, legacy | Full-featured but opaque, harder to customize |

**Recommendation:** Start with `authentication-zero` for production features.

```ruby
# Gemfile
gem "authentication-zero", "~> 4.0"
```

**Authorization:** Use `action_policy` (modern, faster) over Pundit:
```ruby
# Gemfile
gem "action_policy", "~> 0.7"
```

### 3.3 Multi-Tenancy

```ruby
gem "acts_as_tenant", "~> 1.0"
```

### 3.4 Background Jobs (Already Included)

Rails 8 ships with Solid Queue - no additional gems needed.

### 3.5 Billing & Payments

**Decision:** Use `pay` gem for Stripe/Paddle integration.

```ruby
# Gemfile
gem "pay", "~> 11.0"
gem "stripe", "~> 13.0" # or 'paddle' gem
```

**Why Pay:**
- Handles webhooks, subscriptions, payment methods
- Supports Stripe, Paddle, Braintree, Lemon Squeezy
- Built-in Rails integration with `pay_customer`

### 3.6 Observability

```ruby
# Gemfile
group :production do
  gem "honeybadger", "~> 5.0"    # Error tracking
  gem "skylight", "~> 6.0"       # Performance monitoring
  gem "lograge", "~> 0.14"       # Structured logging
end
```

### 3.7 Testing

```ruby
group :test do
  gem "minitest-spec-rails", "~> 7.0"  # Minitest with spec syntax
  gem "factory_bot_rails", "~> 6.4"    # Test data
  gem "webmock", "~> 3.24"             # HTTP stubbing
  gem "vcr", "~> 6.3"                  # Record/replay API calls
  gem "capybara", "~> 3.40"            # System tests
end
```

---

## 4. Key Architectural Patterns

### 4.1 Service Objects vs Interactors vs Operations

**Decision:** Use plain Ruby service objects (no gem) for clarity and control.

**Directory Structure:**
```
app/services/
├── application_service.rb    # Base class
├── councils/
│   ├── create.rb
│   ├── update.rb
│   └── delete.rb
├── conversations/
│   ├── start.rb
│   ├── add_message.rb
│   └── archive.rb
├── llm/
│   ├── client.rb
│   ├── streaming_handler.rb
│   └── usage_tracker.rb
└── billing/
    ├── charge_for_usage.rb
    └── check_quota.rb
```

**Base Class Pattern:**
```ruby
# app/services/application_service.rb
class ApplicationService
  include ActiveSupport::Rescuable

  def self.call(...)
    new(...).call
  end

  def call
    raise NotImplementedError
  end

  private

  def transaction(&block)
    ActiveRecord::Base.transaction(&block)
  end
end

# Example usage
class Councils::Create < ApplicationService
  def initialize(account, user, params)
    @account = account
    @user = user
    @params = params
  end

  def call
    council = nil
    
    transaction do
      council = @account.councils.create!(@params.merge(user: @user))
      setup_default_advisors(council) if @params[:use_defaults]
    end

    Result.success(council)
  rescue ActiveRecord::RecordInvalid => e
    Result.failure(e.record.errors)
  end

  private

  def setup_default_advisors(council)
    # ...
  end
end

# Result object pattern
class Result
  attr_reader :value, :errors

  def self.success(value)
    new(success: true, value: value)
  end

  def self.failure(errors)
    new(success: false, errors: errors)
  end

  def initialize(success:, value: nil, errors: nil)
    @success = success
    @value = value
    @errors = errors
  end

  def success?
    @success
  end

  def failure?
    !@success
  end
end
```

### 4.2 Adapter Pattern for Multi-Provider LLM

```ruby
# app/services/llm/providers/base.rb
module Llm
  module Providers
    class Base
      def chat(**kwargs)
        raise NotImplementedError
      end

      def models
        raise NotImplementedError
      end

      def validate_model!(model_id)
        return if models.include?(model_id)
        raise Llm::UnknownModel, "Unknown model: #{model_id}"
      end
    end
  end
end
```

### 4.3 Event Handling for Async Processing

Use Rails' built-in `ActiveSupport::Notifications` + Solid Queue jobs:

```ruby
# config/initializers/event_subscriptions.rb
ActiveSupport::Notifications.subscribe("message.created") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  message_id = event.payload[:message_id]
  
  # Enrich message, trigger AI responses asynchronously
  MessageProcessingJob.perform_later(message_id)
end

# Trigger from model
class Message < ApplicationRecord
  after_create_commit :notify_created

  private

  def notify_created
    ActiveSupport::Notifications.instrument("message.created", message_id: id)
  end
end
```

### 4.4 Caching Strategy

**Three-layer approach:**

1. **Solid Cache (database-backed):** Rate limits, session data
2. **Russian Doll caching:** Conversation lists, advisor configs
3. **HTTP caching:** Static assets, API responses via ETags

```ruby
# app/views/conversations/index.html.erb
<% cache [current_account, @conversations.maximum(:updated_at)] do %>
  <%= render @conversations %>
<% end %>

# app/models/conversation.rb
class Conversation < ApplicationRecord
  after_update_commit :touch_council

  private

  def touch_council
    council.touch
  end
end
```

---

## 5. Recommended Directory Structure

```
small-council/
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb
│   │   ├── concerns/
│   │   │   ├── authentication.rb
│   │   │   ├── set_current_account.rb
│   │   │   └── error_handling.rb
│   │   ├── dashboard_controller.rb
│   │   ├── councils_controller.rb
│   │   ├── conversations_controller.rb
│   │   ├── messages_controller.rb
│   │   ├── advisors_controller.rb
│   │   └── settings/
│   │       ├── accounts_controller.rb
│   │       ├── billing_controller.rb
│   │       └── users_controller.rb
│   ├── models/
│   │   ├── application_record.rb
│   │   ├── account.rb
│   │   ├── user.rb
│   │   ├── council.rb
│   │   ├── advisor.rb
│   │   ├── council_advisor.rb
│   │   ├── conversation.rb
│   │   ├── message.rb
│   │   ├── usage_record.rb
│   │   └── concerns/
│   │       ├── tokenable.rb
│   │       └── billable.rb
│   ├── services/
│   │   ├── application_service.rb
│   │   ├── result.rb
│   │   ├── councils/
│   │   ├── conversations/
│   │   ├── llm/
│   │   └── billing/
│   ├── jobs/
│   │   ├── application_job.rb
│   │   ├── generate_advisor_response_job.rb
│   │   ├── process_conversation_job.rb
│   │   └── sync_usage_job.rb
│   ├── policies/
│   │   ├── application_policy.rb
│   │   ├── council_policy.rb
│   │   ├── conversation_policy.rb
│   │   └── advisor_policy.rb
│   ├── channels/
│   │   └── turbo/
│   │       └── streams_channel.rb
│   ├── components/
│   │   └── ui/                    # ViewComponent or plain partials
│   ├── views/
│   └── assets/
├── config/
│   ├── initializers/
│   │   ├── acts_as_tenant.rb
│   │   ├── ruby_llm.rb
│   │   ├── action_policy.rb
│   │   └── pay.rb
│   ├── queue.yml                  # Solid Queue config
│   └── recurring.yml              # Solid Queue recurring jobs
├── db/
├── test/
│   ├── factories/
│   ├── services/
│   ├── policies/
│   ├── system/
│   └── fixtures/
└── .ai/
    ├── docs/
    │   ├── features/
    │   └── patterns/
    └── plans/
```

---

## 6. Tiered Recommendations

### 6.1 MVP Tier (Weeks 1-4)

**Must implement:**
- Rails 8 auth generator (or skip auth for demo)
- Single-provider LLM (OpenAI only via `ruby_llm`)
- Scoped multi-tenancy (`acts_as_tenant`)
- Core entities: Accounts, Users, Councils, Conversations, Messages
- Basic streaming via Hotwire
- Simple usage tracking (no billing)

**Skip:**
- OAuth, 2FA
- Multi-provider LLM abstraction
- Billing/subscriptions
- Advanced caching

### 6.2 Production Tier (Weeks 5-12)

**Add:**
- `authentication-zero` for full auth features
- Multi-provider LLM support (OpenAI, Anthropic)
- `pay` gem for Stripe billing
- Usage-based metering with rate limits
- Full authorization with `action_policy`
- Comprehensive test suite (VCR for API mocking)
- Error tracking (Honeybadger)
- Performance monitoring (Skylight)

### 6.3 Scale Tier (Future)

**Consider:**
- Read replicas for conversation history
- Redis for session/cache if Solid Cache bottlenecks
- Background AI processing queues per-priority
- Conversation archiving to cold storage
- Custom model fine-tuning pipeline

---

## 7. Migration/Implementation Phases

### Phase 1: Foundation (Week 1)
1. Set up authentication (Rails 8 generator or auth-zero)
2. Configure `acts_as_tenant` multi-tenancy
3. Create core migrations (accounts, users, councils, advisors)
4. Set up `ruby_llm` with OpenAI
5. Basic council CRUD

### Phase 2: Core Conversations (Week 2)
1. Conversation and message models
2. Basic LLM integration (non-streaming)
3. Simple UI with Hotwire
4. Advisor persona system

### Phase 3: Streaming & Polish (Week 3)
1. Implement streaming responses
2. Add ActionCable/Turbo Streams for real-time updates
3. Error handling and retry logic
4. Usage tracking

### Phase 4: Production Hardening (Week 4)
1. Multi-provider LLM support
2. Rate limiting
3. Billing integration (Pay gem)
4. Authorization policies
5. Comprehensive tests

---

## Verification

Before implementation, verify:

- [ ] Database schema supports conversation volume estimates (1000 messages/conversation)
- [ ] Solid Queue configuration handles expected AI request concurrency
- [ ] API keys configured for at least 2 LLM providers
- [ ] Rate limits tested against provider documentation
- [ ] Streaming works with Turbo Streams in production-like environment
- [ ] Multi-tenancy isolation verified (cannot access other accounts' data)

---

## Doc Impact

- **Create:** `.ai/docs/features/authentication.md`
- **Create:** `.ai/docs/features/multi-tenancy.md`
- **Create:** `.ai/docs/features/llm-integration.md`
- **Create:** `.ai/docs/patterns/service-objects.md`
- **Update:** `.ai/docs/overview.md` with tech stack details
- **Update:** `.ai/MEMORY.md` with commands and conventions

---

## Rollback

If architecture proves unsuitable:
1. Migration files can be rolled back/replaced
2. Service objects are plain Ruby—easy to refactor
3. `ruby_llm` adapter can be swapped without changing business logic
4. Multi-tenancy scope can migrate to RLS later if needed (data migration required)

---

## Open Questions

1. **Billing model:** Metered usage only, or subscription tiers + overages?
2. **AI response workflow:** All advisors respond simultaneously or sequentially?
3. **Data retention:** How long to keep conversation history for inactive accounts?

**Approve this plan?**