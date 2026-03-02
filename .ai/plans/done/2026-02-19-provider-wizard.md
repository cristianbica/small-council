# Provider Integration Wizard - Implementation Plan

Date: 2026-02-19

## Overview
Create a wizard-style, step-by-step flow for integrating AI providers with testing and configuration.

## Wizard Steps

### Step 1: Select Provider Type
- Show available providers as cards with icons
- Options: OpenAI, Anthropic, GitHub Models
- Each card shows provider logo/icon and brief description
- User clicks to proceed

### Step 2: Authenticate (API Key)
- Show provider-specific API key input
- OpenAI: API Key + optional Organization ID
- Anthropic: API Key only
- GitHub Models: GitHub Personal Access Token
- Show helper text with links to provider docs
- Masked input for security

### Step 3: Test Connection
- Backend validates the API key by making a test call
- Shows loading state during test
- Success: Shows green checkmark + available models
- Failure: Shows error message with helpful guidance
- User can retry or go back

### Step 4: Configure & Save
- Optional: Custom name for the provider (defaults to "OpenAI Production", etc.)
- Toggle: Enable/Disable (default: enabled)
- Review and confirm
- Save button

## Technical Implementation

### New Controller Actions
Add to `ProvidersController`:
- `wizard` - Main wizard action (handles all steps)
- `wizard_step` - Process each step
- `test_connection` - AJAX endpoint to test API key

### New Views
1. `app/views/providers/wizard.html.erb` - Main wizard container
2. `app/views/providers/wizard/_step1.html.erb` - Select provider type
3. `app/views/providers/wizard/_step2.html.erb` - Enter credentials
4. `app/views/providers/wizard/_step3.html.erb` - Test connection
5. `app/views/providers/wizard/_step4.html.erb` - Configure & save

### New Service
Create `ProviderConnectionTester` service:
- Tests API key validity
- Fetches available models
- Returns success/failure with details

### Routes
Add:
```ruby
get '/providers/wizard', to: 'providers#wizard', as: :provider_wizard
post '/providers/wizard/step', to: 'providers#wizard_step', as: :provider_wizard_step
post '/providers/test_connection', to: 'providers#test_connection', as: :test_provider_connection
```

### JavaScript (Stimulus)
Create `provider_wizard_controller.js`:
- Handle step transitions
- Show/hide steps
- Handle test connection AJAX
- Form validation

## Provider-Specific Details

### OpenAI
- **API Key**: Required, starts with "sk-"
- **Organization ID**: Optional, starts with "org-"
- **Test Call**: List models endpoint (cheap/free)
- **Docs Link**: https://platform.openai.com/api-keys

### Anthropic
- **API Key**: Required
- **Test Call**: List models or simple message
- **Docs Link**: https://console.anthropic.com/settings/keys

### GitHub Models
- **Token**: GitHub Personal Access Token
- **Scope**: Needs no special scope for public models
- **Test Call**: List available models
- **Docs Link**: https://github.com/settings/tokens

## UI/UX Design

### Step 1: Provider Selection
```
┌─────────────────────────────────────────┐
│  Choose your AI Provider                │
│                                         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐ │
│  │ OpenAI  │  │Anthropic│  │  GitHub │ │
│  │  🤖    │  │  🧠    │  │  Models │ │
│  │         │  │         │  │         │ │
│  │ GPT-4,  │  │ Claude, │  │ Phi,    │ │
│  │ GPT-3.5 │  │ Claude  │  │ Llama,  │ │
│  │         │  │ Instant │  │ Mistral │ │
│  └─────────┘  └─────────┘  └─────────┘ │
│                                         │
└─────────────────────────────────────────┘
```

### Step 2: Authentication
```
┌─────────────────────────────────────────┐
│  Step 2: Authenticate with OpenAI      │
│  ← Back                                 │
│                                         │
│  API Key *                              │
│  ┌─────────────────────────────────┐   │
│  │ sk-...                          │   │
│  └─────────────────────────────────┘   │
│  Find your API key →                    │
│                                         │
│  Organization ID (Optional)             │
│  ┌─────────────────────────────────┐   │
│  │ org-...                         │   │
│  └─────────────────────────────────┘   │
│  Only needed for enterprise accounts    │
│                                         │
│  [Continue →]                          │
└─────────────────────────────────────────┘
```

### Step 3: Test Connection
```
┌─────────────────────────────────────────┐
│  Step 3: Test Connection               │
│  ← Back                                 │
│                                         │
│  [🔄 Testing...]                       │
│                                         │
│  OR                                     │
│                                         │
│  ✅ Connection successful!               │
│  Found 8 models:                        │
│  • gpt-4-turbo                          │
│  • gpt-4                                │
│  • gpt-3.5-turbo                        │
│  • ...                                  │
│                                         │
│  [Continue →]                          │
│                                         │
│  OR                                     │
│                                         │
│  ❌ Connection failed                   │
│  Invalid API key. Please check and      │
│  try again.                             │
│                                         │
│  [Try Again]  [← Back]                 │
└─────────────────────────────────────────┘
```

### Step 4: Configure & Save
```
┌─────────────────────────────────────────┐
│  Step 4: Configure Provider            │
│  ← Back                                 │
│                                         │
│  Name (Optional)                        │
│  ┌─────────────────────────────────┐   │
│  │ OpenAI Production               │   │
│  └─────────────────────────────────┘   │
│  A friendly name to identify this       │
│  provider                               │
│                                         │
│  Enabled                                │
│  ┌────┐                                 │
│  │ ✅ │  Provider is active             │
│  └────┘                                 │
│                                         │
│  Summary:                               │
│  • Type: OpenAI                         │
│  • Models: 8 available                  │
│  • Status: Ready to use                 │
│                                         │
│  [Save Provider]                        │
└─────────────────────────────────────────┘
```

## Files to Create/Modify

### New Files
1. `app/services/provider_connection_tester.rb` - Test service
2. `app/views/providers/wizard.html.erb` - Main wizard
3. `app/views/providers/wizard/_step1.html.erb` - Step 1
4. `app/views/providers/wizard/_step2.html.erb` - Step 2
5. `app/views/providers/wizard/_step3.html.erb` - Step 3
6. `app/views/providers/wizard/_step4.html.erb` - Step 4

### Modified Files
1. `app/controllers/providers_controller.rb` - Add wizard actions
2. `config/routes.rb` - Add wizard routes
3. `app/views/providers/index.html.erb` - Update "Add Provider" button to use wizard

## Implementation Details

### ProviderConnectionTester Service
```ruby
class ProviderConnectionTester
  def self.test(provider_type, api_key, organization_id = nil)
    case provider_type
    when "openai"
      test_openai(api_key, organization_id)
    when "anthropic"
      test_anthropic(api_key)
    when "github"
      test_github_models(api_key)
    else
      { success: false, error: "Unknown provider type" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  private

  def self.test_openai(api_key, organization_id)
    client = OpenAI::Client.new(
      access_token: api_key,
      organization_id: organization_id
    )
    
    response = client.models.list
    models = response["data"].map { |m| m["id"] }
    
    { success: true, models: models }
  rescue OpenAI::Error => e
    { success: false, error: e.message }
  end

  def self.test_anthropic(api_key)
    client = Anthropic::Client.new(access_token: api_key)
    
    # Make a minimal API call to validate
    response = client.models.list
    models = response["models"].map { |m| m["display_name"] }
    
    { success: true, models: models }
  rescue => e
    { success: false, error: e.message }
  end

  def self.test_github_models(api_key)
    # GitHub Models uses Azure endpoint
    client = OpenAI::Client.new(
      access_token: api_key,
      uri_base: "https://models.inference.ai.azure.com"
    )
    
    response = client.models.list
    models = response["data"].map { |m| m["id"] }
    
    { success: true, models: models }
  rescue => e
    { success: false, error: e.message }
  end
end
```

### Wizard Session Management
Store wizard state in session:
```ruby
session[:provider_wizard] = {
  step: 1,
  provider_type: "openai",
  api_key: "encrypted...",
  organization_id: "org-...",
  name: "OpenAI Production",
  enabled: true,
  tested: true,
  available_models: [...]
}
```

Clear session on completion or cancellation.

## Acceptance Criteria

- [ ] Step 1: Provider selection page with cards
- [ ] Step 2: Authentication form with provider-specific fields
- [ ] Step 3: Connection test with loading state
- [ ] Step 4: Configuration form with name and enable toggle
- [ ] Connection test validates API key before saving
- [ ] Shows available models after successful test
- [ ] User can go back to previous steps
- [ ] Session maintains wizard state
- [ ] All existing tests pass
- [ ] New tests for wizard flow

## Timeline Estimate

- Service + Controller: 1.5 hours
- Views (4 steps): 2 hours
- JavaScript/Stimulus: 1 hour
- Routes + Integration: 0.5 hours
- Testing: 1 hour
- **Total: ~6 hours**
