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
# Enable a model
LLM::ModelManager.enable_model(account, provider, "gpt-4o")

# Disable a model
LLM::ModelManager.disable_model(account, provider, "gpt-4o")
```

### Model Lifecycle
- **Enabled**: Available for advisors to use
- **Disabled**: Hidden from advisor configuration but preserved in database
- Models store metadata (capabilities, pricing, context window) from ruby_llm

## Technical

### Routes
```
/providers              # index, new, create
/providers/:id/edit     # edit, update
/providers/:id          # destroy
/providers/:id/models   # model management UI
```

### Models
- `Provider`: name, provider_type, credentials (encrypted), organization_id, enabled
- `Provider.has_many :llm_models, dependent: :destroy`
- `LlmModel`: name, identifier, enabled, metadata (capabilities, pricing), provider reference

### LLM::Client

The `LLM::Client` class handles all provider operations:

```ruby
# Provider-level operations (no model required)
client = LLM::Client.new(provider: provider)
client.list_models      # Fetch available models from API
client.test_connection  # Validate API credentials

# Model-level operations (requires model)
client = LLM::Client.new(provider: provider, model: llm_model)
client.info             # Get model metadata from ruby_llm
client.supports?(:vision)  # Check capability support
client.chat(messages, system_prompt: "...")  # Execute chat completion
```

### LLM::ModelManager

Manages model lifecycle and discovery:

```ruby
# List all available models across all providers
models = LLM::ModelManager.available_models(account)
# Returns array of ModelInfo structs with provider, model_id, name, enabled, capabilities

# Enable a model (fetches metadata from ruby_llm)
llm_model = LLM::ModelManager.enable_model(account, provider, "gpt-4o")

# Disable a model
LLM::ModelManager.disable_model(account, provider, "gpt-4o")
```

### Encrypted Credentials
```ruby
class Provider < ApplicationRecord
  encrypts :credentials, deterministic: false
end
```

Requirements:
- `RAILS_MASTER_KEY` env var in production
- `config/credentials.yml.enc` with active_record_encryption keys
- Test environment uses deterministic keys (see `config/initializers/active_record_encryption.rb`)

### Controllers
- `ProvidersController`: Standard CRUD + wizard flow
- `Provider::ModelsController`: Model management (enable/disable)
- All account users can manage providers (Phase 1 - no role restrictions)

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

Every API call creates a UsageRecord:

```ruby
UsageRecord.create!(
  account: account,
  provider: provider.provider_type,
  model: llm_model.identifier,
  input_tokens: tokens[:input],
  output_tokens: tokens[:output],
  cost_cents: calculate_cost(tokens)
)
```

## Implementation Notes

- Provider type is immutable after creation (UI reflects this)
- Models are soft-enabled/disabled (not deleted) for historical references
- Each advisor references one LlmModel
- Changing an advisor's model requires selecting from account's available models
- Model metadata is synced from ruby_llm on enable
