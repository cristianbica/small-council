# Providers

AI provider management for LLM API credentials and model configuration.

## Overview

- **Provider** = AI service credentials (OpenAI, OpenRouter)
- API keys are encrypted at rest using Rails encrypted attributes
- Each account manages its own providers independently
- Multiple providers per account supported

## Supported Providers

| Provider | Type | Models |
|----------|------|--------|
| OpenAI | `openai` | GPT-4o, GPT-4o-mini, o1, o3-mini, etc. |
| OpenRouter | `openrouter` | Multi-provider access (OpenAI, Anthropic, Google, etc.) |

## Provider Setup Wizard

Adding a provider uses a 4-step wizard flow:

1. **Select Provider** - Choose OpenAI or OpenRouter from the provider type dropdown
2. **Enter Credentials** - Provide API key (and organization ID for OpenAI if applicable)
3. **Test Connection** - System validates the API key by making a test call
4. **Name Provider** - Give the provider a descriptive name (e.g., "OpenAI Production")

## Model Management

After creating a provider, models are managed through the UI:

### Available Models
- Models are fetched dynamically from the provider's API
- Each model shows capabilities (chat, vision, JSON mode, functions)
- Models can be enabled or disabled per account

### Enable/Disable Models
```ruby
# Via AI::ModelManager service
AI::ModelManager.enable_model(account, provider, model_id)
AI::ModelManager.disable_model(account, provider, model_id)
```

Models can also be toggled via the UI at `/providers/:id/models` (toggle switch per model).

### Model Lifecycle
- **Enabled**: Available for advisors to use
- **Disabled**: Hidden from advisor configuration but preserved in database
- Models store metadata (capabilities, pricing, context window) from ruby_llm

## Technical

### Routes
```
/providers                    # index, new, create
/providers/:id/edit           # edit, update
/providers/:id                # destroy
/providers/wizard             # GET
/providers/wizard_step        # POST
/providers/wizard_back        # POST
/providers/wizard_cancel      # POST
/providers/test_connection    # POST
/providers/models             # GET (collection)
/providers/:id/models         # GET (member)
/providers/toggle_model       # POST
```

### Models
- `Provider`: name, provider_type, credentials (encrypted), organization_id, enabled
- `Provider.has_many :llm_models, dependent: :destroy`
- `LlmModel`: name, identifier, enabled, metadata (capabilities, pricing), provider reference

### AI::Client (provider operations)

Provider-level class methods (no model instance required):

```ruby
# Test connection
AI::Client.test_connection(provider: provider)
# => { success: true, model: "gpt-4o-mini" } or { success: false, error: "..." }

# List available models
AI::Client.list_models(provider: provider)
# => [{ id: "gpt-4o", name: "GPT-4o", capabilities: {...} }, ...]
```

### AI::ModelManager

Manages model lifecycle and sync:

```ruby
# Enumerate available models for account/provider(s)
AI::ModelManager.available_models(account)

# Enable/disable a model
AI::ModelManager.enable_model(account, provider, model_id)
AI::ModelManager.disable_model(account, provider, model_id)
```

### Encrypted Credentials
```ruby
class Provider < ApplicationRecord
  encrypts :credentials
end
```

Requirements:
- `RAILS_MASTER_KEY` env var in production
- `config/credentials.yml.enc` with active_record_encryption keys
- Test environment uses deterministic keys (see `config/initializers/active_record_encryption.rb`)

### Controllers
- `ProvidersController`: Standard CRUD + wizard flow + model toggle
- All account users can manage providers (no role restrictions currently)

### Access Control
- Scoped to account via acts_as_tenant
- All authenticated account users can view/create/edit/destroy
- Admin-only restriction planned for Phase 2

## Security

- API keys encrypted with AES-256-GCM
- Keys never logged or displayed in UI
- Only stored encrypted in database
- Decryption only happens when making API calls

## Usage Tracking Integration

`UsageRecord` is created automatically inside `AI::Client#chat` — no manual tracking needed:

```ruby
# Auto-created by AI::Client#track_usage on every successful chat() call
UsageRecord.create!(
  account: context[:account] || context[:space]&.account,
  provider: model.provider.provider_type,
  model: model.identifier,
  input_tokens: ...,
  output_tokens: ...,
  cost_cents: ...,
  message: context[:message],
  recorded_at: Time.current
)
```

## Implementation Notes

- Provider type is immutable after creation (UI reflects this)
- Models are soft-enabled/disabled (not deleted) for historical references
- Each advisor references one LlmModel
- Changing an advisor's model requires selecting from account's available models
- Model metadata/capabilities are populated from ruby_llm on enable
