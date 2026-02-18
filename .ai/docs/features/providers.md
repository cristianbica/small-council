# Providers

AI provider management for LLM API credentials and model configuration.

## Overview

- **Provider** = AI service credentials (OpenAI, Anthropic, GitHub Models)
- API keys are encrypted at rest using Rails encrypted attributes
- Each account manages its own providers independently
- Multiple providers per account supported

## Supported Providers

| Provider | Type | Models |
|----------|------|--------|
| OpenAI | `openai` | GPT-4, GPT-3.5, etc. |
| Anthropic | `anthropic` | Claude 3 series |
| GitHub Models | `github_models` | OpenAI-compatible on Azure |

## Usage

### Adding a Provider
1. Navigate to "AI Providers" in navigation
2. Click "Add Provider"
3. Enter:
   - Name (e.g., "OpenAI Production")
   - Provider type (dropdown)
   - API key (encrypted on save)
   - Organization ID (OpenAI only, optional)
4. Save - API key is encrypted immediately

### Managing Models
Providers are created with models via console/seeds:

```ruby
provider = account.providers.create!(
  name: "OpenAI",
  provider_type: "openai",
  api_key: "sk-..."
)
provider.llm_models.create!(
  account: account,
  name: "GPT-4",
  identifier: "gpt-4"
)
```

UI for model management coming in Phase 2.

## Technical

### Routes
```
/providers              # index, new, create
/providers/:id/edit     # edit, update
/providers/:id          # destroy
```

### Models
- `Provider`: name, provider_type, credentials (encrypted), organization_id, enabled
- `Provider.has_many :llm_models, dependent: :destroy`
- `LlmModel`: name, identifier, enabled, deprecated, deleted_at (soft delete)

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
- `ProvidersController`: Standard CRUD
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
- Soft delete on models (deleted_at) for historical references
- Each advisor references one LlmModel
- Changing an advisor's model requires selecting from account's available models
