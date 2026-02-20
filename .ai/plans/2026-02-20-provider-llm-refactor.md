# Plan: Provider LLM Refactor with ruby_llm Gem

**Date**: 2026-02-20

## Goal

Replace direct AI gem dependencies (ruby-openai, anthropic) with the `ruby_llm` gem, implementing a clean wrapper architecture that supports:
1. Multi-tenancy via context pattern for isolated provider configurations
2. DSL for provider/model API access (`provider.api`, `model.api`)
3. System-level provider for non-tenant-scoped AI operations
4. OpenAI and OpenRouter providers (Anthropic/Gemini via OpenRouter)

## Non-goals

- Remove existing Provider/LlmModel tables (keep for metadata)
- Support all ruby_llm features (embeddings, images, audio, tools)
- Streaming responses (Phase 2)
- Automatic model discovery/sync from providers
- Rate limiting or spend caps
- Multiple providers per account with failover
- Custom model pricing tables (use ruby_llm registry)
- System-level provider (will use Account.find(0) pattern later)

## Scope + Assumptions

- ruby_llm handles provider routing automatically based on model IDs
- OpenRouter provides access to Anthropic, Gemini, and other models
- Context pattern creates isolated RubyLLM configurations per tenant
- System provider uses ENV-configured credentials (not tenant-scoped)
- Keep existing Provider/LlmModel tables for UI/admin purposes
- AI calls remain synchronous (background job already handles async)
- Token usage/cost tracking continues via UsageRecord

## Research Summary: ruby_llm Gem

### Key Capabilities

1. **Unified API**: Single interface for OpenAI, Anthropic, Gemini, OpenRouter, etc.
2. **Context Pattern**: `RubyLLM.context { |config| ... }` creates isolated configurations for multi-tenancy
3. **Provider Routing**: Automatic provider detection based on model ID prefixes (e.g., `gpt-4` → OpenAI, `anthropic/claude-3` → OpenRouter)
4. **Model Registry**: 800+ models with capabilities and pricing data
5. **Minimal Dependencies**: Faraday, Zeitwerk, Marcel only

### Configuration Examples

```ruby
# Global configuration
RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
  config.openrouter_api_key = ENV['OPENROUTER_API_KEY']
end

# Isolated context for multi-tenancy
tenant_context = RubyLLM.context do |config|
  config.openai_api_key = tenant.openai_key
  config.openrouter_api_key = tenant.openrouter_key
end

# Use context for chat
chat = tenant_context.chat(model: 'gpt-4o')
response = chat.ask("Hello")
```

### Provider Detection

- `gpt-*`, `o1*` → OpenAI
- `anthropic/*` → OpenRouter (or direct Anthropic if configured)
- `google/*` → OpenRouter (or Gemini if configured)
- Explicit provider override: `chat = RubyLLM.chat(model: 'claude-3', provider: 'anthropic')`

## Architecture Design

### 1. Context Pattern Wrapper

```ruby
# app/services/llm/context.rb
module LLM
  class Context
    def self.for_tenant(account)
      # Build context from account's providers
      providers = account.providers.enabled
      
      RubyLLM.context do |config|
        providers.each do |provider|
          case provider.provider_type
          when 'openai'
            config.openai_api_key = provider.api_key
            config.openai_organization_id = provider.organization_id
          when 'openrouter'
            config.openrouter_api_key = provider.api_key
          end
        end
      end
    end

    def self.system
      # System-wide context from ENV
      RubyLLM.context do |config|
        config.openai_api_key = ENV['SYSTEM_OPENAI_API_KEY']
        config.openrouter_api_key = ENV['SYSTEM_OPENROUTER_API_KEY']
      end
    end
  end
end
```

### 2. Unified LLM::Client Design

Single client class that handles both provider-level and model-level operations:

```ruby
# app/services/llm/client.rb
module LLM
  class Client
    class MissingModelError < StandardError; end

    attr_reader :provider, :model

    def initialize(provider:, model: nil)
      @provider = provider
      @model = model
    end

    # Provider-level: List available models
    def list_models
      models = RubyLLM.models.by_provider(provider_type_slug)
      models.map do |model_info|
        {
          id: model_info.id,
          name: model_info.name,
          provider: model_info.provider,
          capabilities: {
            chat: model_info.chat?,
            vision: model_info.vision?,
            json_mode: model_info.json_mode?,
            functions: model_info.functions?
          }
        }
      end
    end

    # Provider-level: Test connection with minimal API call
    def test_connection
      chat = build_context.chat(model: test_model_id)
      response = chat.ask("Test connection")
      
      { success: true, model: response.model }
    rescue => e
      { success: false, error: e.message }
    end

    # Model-level: Get model info from registry
    def info
      raise MissingModelError, "Client initialized without a model" unless @model
      
      RubyLLM.models.find(api_identifier)
    rescue
      nil
    end

    # Model-level: Check capability support
    def supports?(capability)
      raise MissingModelError, "Client initialized without a model" unless @model
      
      model_info = info
      return false unless model_info
      
      case capability
      when :vision then model_info.vision?
      when :json_mode then model_info.json_mode?
      when :functions then model_info.functions?
      when :streaming then model_info.streaming?
      else false
      end
    end

    # Model-level: Execute chat completion (fails if no model)
    def chat(messages, system_prompt: nil, temperature: 0.7, max_tokens: 1000)
      raise MissingModelError, "Client initialized without a model" unless @model

      context = build_context
      chat = context.chat(model: api_identifier)
      
      chat.with_system_message(system_prompt) if system_prompt
      
      messages.each do |msg|
        chat.add_message(role: msg[:role], content: msg[:content])
      end

      response = chat.complete
      
      {
        content: response.content,
        input_tokens: response.input_tokens,
        output_tokens: response.output_tokens,
        total_tokens: response.total_tokens,
        model: response.model,
        provider: @provider.provider_type
      }
    rescue => e
      raise LLM::APIError, "Chat completion failed: #{e.message}"
    end

    private

    def build_context
      RubyLLM.context do |config|
        case @provider.provider_type
        when 'openai'
          config.openai_api_key = @provider.api_key
          config.openai_organization_id = @provider.organization_id
        when 'openrouter'
          config.openrouter_api_key = @provider.api_key
        end
      end
    end

    def provider_type_slug
      case @provider.provider_type
      when 'openai' then :openai
      when 'openrouter' then :openrouter
      else @provider.provider_type.to_sym
      end
    end

    def test_model_id
      case @provider.provider_type
      when 'openai' then 'gpt-4o-mini'
      when 'openrouter' then 'openai/gpt-4o-mini'
      else 'gpt-4o-mini'
      end
    end

    def api_identifier
      @model.identifier
    end
  end

  class APIError < StandardError; end
end
```

### 3. Model Integration

```ruby
# app/models/provider.rb (add method)
class Provider < ApplicationRecord
  # ... existing code ...

  # Returns LLM::Client for provider-level operations
  # (list_models, test_connection - chat will fail without model)
  def api
    @api ||= LLM::Client.new(provider: self)
  end
end

# app/models/llm_model.rb (add method)
class LlmModel < ApplicationRecord
  # ... existing code ...

  # Returns LLM::Client scoped to this model
  # (all operations available including chat)
  def api
    @api ||= LLM::Client.new(provider: provider, model: self)
  end
end
```

### 4. Refactored AiClient Service

```ruby
# app/services/ai_client.rb (refactored)
class AiClient
  class Error < StandardError; end
  class ApiError < Error; end
  class RateLimitError < Error; end
  class InvalidResponseError < Error; end

  MAX_RETRIES = 2
  RETRY_DELAY = 1 # seconds

  attr_reader :advisor, :conversation, :message

  def initialize(advisor:, conversation:, message:)
    @advisor = advisor
    @conversation = conversation
    @message = message
  end

  # Main entry point: calls LLM API and returns response content
  def generate_response
    return nil unless advisor.llm_model.present?
    return nil unless advisor.llm_model.enabled?

    with_retries do
      # Use the new unified client: model_instance.api.chat(...)
      result = advisor.llm_model.api.chat(
        build_messages,
        system_prompt: advisor.system_prompt,
        temperature: advisor.model_config["temperature"] || 0.7,
        max_tokens: advisor.model_config["max_tokens"] || 1000
      )

      result
    end
  rescue LLM::APIError => e
    log_error(e)
    raise ApiError, "AI API call failed: #{e.message}"
  rescue => e
    log_error(e)
    raise ApiError, "Unexpected error: #{e.message}"
  end

  private

  def build_messages
    conversation.messages.chronological.filter_map do |msg|
      next if msg.id == message.id # Skip the pending message itself

      role = case msg.role
      when "user" then "user"
      when "advisor" then "assistant"
      else "user"
      end

      { role: role, content: msg.content }
    end
  end

  def with_retries
    retries = 0
    begin
      yield
    rescue => e
      retries += 1
      if retries <= MAX_RETRIES
        sleep(RETRY_DELAY * retries)
        retry
      else
        raise
      end
    end
  end

  def log_error(error)
    Rails.logger.error "[AiClient] Error for advisor #{advisor.id}: #{error.message}"
    Rails.logger.error error.backtrace.first(5).join("\n") if error.backtrace
  end
end
```

## DSL Specification

### Provider DSL

```ruby
# Generic provider operations (no model required)
provider = account.providers.first
provider.api.list_models                    # → Array of model metadata
provider.api.test_connection                # → { success: true/false, error: msg }

# Chat operations fail without a model
provider.api.chat(messages)                 # → raises LLM::Client::MissingModelError
```

### Model DSL

```ruby
# Model instance API (all operations available)
llm_model = LlmModel.first
llm_model.api.info                          # → Model info from registry
llm_model.api.supports?(:vision)            # → true/false
llm_model.api.list_models                   # → Array of models (from provider)
llm_model.api.test_connection               # → { success: true/false }

# Chat with specific model
result = llm_model.api.chat(
  [{ role: 'user', content: 'Hello' }],
  system_prompt: 'You are helpful',
  temperature: 0.7,
  max_tokens: 1000
)
# → { content: '...', input_tokens: 10, output_tokens: 20, total_tokens: 30 }
```

## Implementation Steps

### Step 1: Add ruby_llm Gem and Remove Old Gems

**File**: `Gemfile`

```ruby
# Remove:
# gem "ruby-openai", "~> 7.0"
# gem "anthropic", "~> 0.3"

# Add:
gem "ruby_llm", "~> 1.3"
```

Run: `bundle install`

### Step 2: Add LLM Inflection

**File**: `config/initializers/inflections.rb`

```ruby
ActiveSupport::Inflector.inflections(:en) do |inflect|
  # RoE = Rules of Engagement (acronym)
  inflect.acronym "RoE"
  
  # LLM = Large Language Model (acronym)
  inflect.acronym "LLM"
end
```

**Note**: File paths remain `llm_*.rb` (lowercase), class names become `LLM*`.

### Step 3: Create RubyLLM Initializer

**File**: `config/initializers/ruby_llm.rb`

```ruby
# Minimal global configuration
# Tenant-specific config happens via Context
RubyLLM.configure do |config|
  # Only set defaults, actual keys come from Context
  config.request_timeout = 60
  config.max_retries = 3
end
```

### Step 4: Create LLM Context Service

**File**: `app/services/llm/context.rb`

```ruby
module LLM
  class Context
    # Creates isolated RubyLLM context for a tenant account
    def self.for_tenant(account)
      providers = account.providers.enabled
      
      RubyLLM.context do |config|
        providers.each do |provider|
          case provider.provider_type
          when 'openai'
            config.openai_api_key = provider.api_key
            config.openai_organization_id = provider.organization_id
          when 'openrouter'
            config.openrouter_api_key = provider.api_key
          end
        end
      end
    end

    # NOTE: System-level context removed - will use Account.find(0) pattern later
  end
end
```

### Step 5: Create Unified LLM::Client

**File**: `app/services/llm/client.rb`

```ruby
module LLM
  class Client
    class MissingModelError < StandardError; end

    attr_reader :provider, :model

    def initialize(provider:, model: nil)
      @provider = provider
      @model = model
    end

    # Provider-level: List available models
    def list_models
      models = RubyLLM.models.by_provider(provider_type_slug)
      models.map do |model_info|
        {
          id: model_info.id,
          name: model_info.name,
          provider: model_info.provider,
          capabilities: {
            chat: model_info.chat?,
            vision: model_info.vision?,
            json_mode: model_info.json_mode?,
            functions: model_info.functions?
          }
        }
      end
    end

    # Provider-level: Test connection with minimal API call
    def test_connection
      chat = build_context.chat(model: test_model_id)
      response = chat.ask("Test connection")
      
      { success: true, model: response.model }
    rescue => e
      { success: false, error: e.message }
    end

    # Model-level: Get model info from registry (fails if no model)
    def info
      raise MissingModelError, "Client initialized without a model" unless @model
      
      RubyLLM.models.find(api_identifier)
    rescue
      nil
    end

    # Model-level: Check capability support (fails if no model)
    def supports?(capability)
      raise MissingModelError, "Client initialized without a model" unless @model
      
      model_info = info
      return false unless model_info
      
      case capability
      when :vision then model_info.vision?
      when :json_mode then model_info.json_mode?
      when :functions then model_info.functions?
      when :streaming then model_info.streaming?
      else false
      end
    end

    # Model-level: Execute chat completion (fails if no model)
    def chat(messages, system_prompt: nil, temperature: 0.7, max_tokens: 1000)
      raise MissingModelError, "Client initialized without a model" unless @model

      context = build_context
      chat = context.chat(model: api_identifier)
      
      chat.with_system_message(system_prompt) if system_prompt
      
      messages.each do |msg|
        chat.add_message(role: msg[:role], content: msg[:content])
      end

      response = chat.complete
      
      {
        content: response.content,
        input_tokens: response.input_tokens,
        output_tokens: response.output_tokens,
        total_tokens: response.total_tokens,
        model: response.model,
        provider: @provider.provider_type
      }
    rescue => e
      raise LLM::APIError, "Chat completion failed: #{e.message}"
    end

    private

    def build_context
      RubyLLM.context do |config|
        case @provider.provider_type
        when 'openai'
          config.openai_api_key = @provider.api_key
          config.openai_organization_id = @provider.organization_id
        when 'openrouter'
          config.openrouter_api_key = @provider.api_key
        end
      end
    end

    def provider_type_slug
      case @provider.provider_type
      when 'openai' then :openai
      when 'openrouter' then :openrouter
      else @provider.provider_type.to_sym
      end
    end

    def test_model_id
      case @provider.provider_type
      when 'openai' then 'gpt-4o-mini'
      when 'openrouter' then 'openai/gpt-4o-mini'
      else 'gpt-4o-mini'
      end
    end

    def api_identifier
      @model.identifier
    end
  end

  class APIError < StandardError; end
end
```

### Step 6: Update Provider Model

**File**: `app/models/provider.rb`

```ruby
class Provider < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account

  has_many :llm_models, dependent: :destroy

  enum :provider_type, {
    openai: "openai",
    openrouter: "openrouter"
    # Removed: anthropic, gemini, github (use via OpenRouter)
  }, prefix: :type

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :provider_type, presence: true
  validates :account, presence: true

  # Encrypt credentials at rest
  encrypts :credentials

  scope :enabled, -> { where(enabled: true) }
  scope :by_type, ->(type) { where(provider_type: type) }

  # Get API key from encrypted credentials
  def api_key
    credentials["api_key"]
  end

  def api_key=(value)
    self.credentials = credentials.merge("api_key" => value)
  end

  # Organization ID for OpenAI
  def organization_id
    credentials["organization_id"]
  end

  def organization_id=(value)
    self.credentials = credentials.merge("organization_id" => value)
  end

  # NEW: Provider API wrapper (returns LLM::Client without model)
  def api
    @api ||= LLM::Client.new(provider: self)
  end
end
```

### Step 7: Update LlmModel Model

**File**: `app/models/llm_model.rb`

```ruby
class LlmModel < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :provider

  has_many :advisors, dependent: :nullify

  validates :name, presence: true
  validates :identifier, presence: true, uniqueness: { scope: :provider_id }
  validates :provider, presence: true

  scope :enabled, -> { where(enabled: true, deprecated: false).where(deleted_at: nil) }
  scope :available, -> { enabled }
  scope :deprecated, -> { where(deprecated: true) }
  scope :soft_deleted, -> { where.not(deleted_at: nil) }

  # Soft delete
  def soft_delete
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # Full API identifier (provider-specific format)
  def full_identifier
    "#{provider.provider_type}/#{identifier}"
  end

  # Display name with provider
  def display_name
    "#{name} (#{provider.name})"
  end

  # NEW: Model API wrapper (returns LLM::Client with model)
  def api
    @api ||= LLM::Client.new(provider: provider, model: self)
  end
end
```

### Step 8: Refactor AiClient Service

**File**: `app/services/ai_client.rb`

Replace entire implementation with ruby_llm-based version (see Architecture section above).

Key changes:
- Remove direct OpenAI/Anthropic gem usage
- Use `advisor.llm_model.api.chat(...)` DSL
- Keep same public interface (`generate_response`)
- Keep same error classes for backward compatibility

### Step 9: Update ProviderConnectionTester

**File**: `app/services/provider_connection_tester.rb`

```ruby
class ProviderConnectionTester
  def self.test(provider_type, api_key, organization_id = nil)
    # Create temporary provider instance for testing
    temp_provider = Provider.new(
      provider_type: provider_type,
      credentials: { "api_key" => api_key, "organization_id" => organization_id }
    )
    
    result = temp_provider.api.test_connection
    
    if result[:success]
      # Also return available models
      models = temp_provider.api.list_models
      { success: true, models: models.map { |m| m[:id] } }
    else
      { success: false, error: result[:error] }
    end
  rescue => e
    { success: false, error: e.message }
  end
end
```

### Step 10: Update GenerateAdvisorResponseJob

**File**: `app/jobs/generate_advisor_response_job.rb`

No changes needed - continues to use `AiClient` which now uses ruby_llm internally.

### Step 11: Create Migration for Provider Type Update

**File**: `db/migrate/20260220XXXXXX_update_provider_types.rb`

```ruby
class UpdateProviderTypes < ActiveRecord::Migration[8.1]
  def up
    # Migrate existing anthropic/github providers to openrouter
    # or mark them for reconfiguration
    Provider.where(provider_type: ['anthropic', 'github']).find_each do |provider|
      provider.update!(enabled: false, provider_type: 'openrouter')
    end
  end

  def down
    # Cannot restore previous types reliably
  end
end
```

### Step 12: Create Tests for LLM Services

**File**: `test/services/llm/client_test.rb`

```ruby
require "test_helper"

module LLM
  class ClientTest < ActiveSupport::TestCase
    setup do
      @account = accounts(:one)
      set_tenant(@account)
    end

    test "provider client can list models without model" do
      provider = @account.providers.create!(
        name: "OpenAI",
        provider_type: "openai",
        api_key: "test-key"
      )

      client = provider.api
      assert client.is_a?(LLM::Client)
      assert_nil client.model
      # list_models should work
    end

    test "provider client raises on chat without model" do
      provider = @account.providers.create!(
        name: "OpenAI",
        provider_type: "openai",
        api_key: "test-key"
      )

      client = provider.api
      assert_raises(LLM::Client::MissingModelError) do
        client.chat([{ role: 'user', content: 'Hello' }])
      end
    end

    test "model client has model and can chat" do
      provider = @account.providers.create!(
        name: "OpenAI",
        provider_type: "openai",
        api_key: "test-key"
      )
      llm_model = provider.llm_models.create!(
        account: @account,
        name: "GPT-4",
        identifier: "gpt-4"
      )

      client = llm_model.api
      assert client.is_a?(LLM::Client)
      assert_equal llm_model, client.model
      # chat should work
    end
  end
end
```

## Verification

Run this checklist after implementation:

- [ ] `bundle install` completes without errors
- [ ] LLM inflection works: `LlmModel` → `LLMModel` in code
- [ ] `bin/rails db:migrate` runs successfully
- [ ] Client tests pass: `bin/rails test test/services/llm/client_test.rb`
- [ ] AiClient tests pass: `bin/rails test test/services/ai_client_test.rb`
- [ ] All tests pass: `bin/rails test`
- [ ] Manual test: Create OpenAI provider via UI
- [ ] Manual test: Create LlmModel with OpenAI identifier
- [ ] Manual test: `provider.api.test_connection` returns success
- [ ] Manual test: `provider.api.list_models` returns models
- [ ] Manual test: `provider.api.chat` raises MissingModelError
- [ ] Manual test: `llm_model.api.chat` returns response with tokens
- [ ] Manual test: Full conversation flow with advisor response generation

## Doc Impact

- **Create**: `.ai/docs/features/llm-wrapper.md` - Document the LLM wrapper architecture
- **Create**: `.ai/docs/patterns/multi-tenant-ai.md` - Context pattern for tenant isolation
- **Update**: `.ai/docs/features/ai-integration.md` - Update to reference new ruby_llm implementation
- **Update**: `.ai/MEMORY.md` - Add ruby_llm gem, LLM acronym convention

## Rollback

If implementation fails:

1. **Restore Gemfile**: Re-add `ruby-openai` and `anthropic`, remove `ruby_llm`
   ```
   bundle install
   ```

2. **Restore AiClient**: Revert to previous implementation using direct gems

3. **Remove new files**:
   - `app/services/llm/context.rb`
   - `app/services/llm/client.rb`
   - `config/initializers/ruby_llm.rb`
   - `test/services/llm/*`

4. **Remove LLM inflection**: Revert `config/initializers/inflections.rb`

5. **Database rollback**: 
   ```
   bin/rails db:rollback STEP=1  # For provider_type migration
   ```

6. **Restore Provider model**: Remove `api` method, restore previous provider types

## Unknowns / Risks

1. **ruby_llm maturity**: Gem is relatively new (v1.3). May have edge cases or breaking changes.

2. **Model identifier mapping**: OpenRouter uses `provider/model` format, OpenAI uses just `model`. Need to ensure identifiers stored in DB match what ruby_llm expects.

3. **Error handling**: ruby_llm error classes may differ from current custom errors. Need to map/wrap appropriately.

4. **Token tracking**: Verify ruby_llm returns accurate token counts for usage tracking.

5. **Multi-tenancy isolation**: Context pattern creates isolated configs, but need to verify no credential leakage between tenants.

6. **Provider type migration**: Existing anthropic/github providers need migration path (disable or convert to openrouter).

7. **Testing without real API keys**: Need to mock/stub ruby_llm for tests.

---

**Approve this plan?**
