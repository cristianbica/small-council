# Unified AI Generator Service - Implementation Plan

## Architecture

Single service `AIGenerator` that handles multiple generation profiles. Each profile defines:
- What fields to generate
- System prompts for each field
- How to structure the AI request

## Service Design

```ruby
# app/services/ai_generator.rb
class AIGenerator
  class Error < StandardError; end
  class NoModelError < Error; end
  class GenerationError < Error; end
  class UnknownProfileError < Error; end

  PROFILES = {
    advisor: {
      fields: [:name, :short_description, :system_prompt],
      system_prompt: <<~PROMPT,
        You are an expert at creating AI advisor profiles.
        Given a concept/role description, generate:
        1. name: Concise (2-4 words, professional, suitable as an identifier)
        2. short_description: Brief (under 100 chars, for list views)
        3. system_prompt: Comprehensive (2-4 paragraphs defining personality, expertise, tone, boundaries)
        
        Return ONLY valid JSON with these exact keys.
      PROMPT
      output_format: :json
    },
    
    council: {
      fields: [:description],
      system_prompt: <<~PROMPT,
        You are an expert at creating compelling council descriptions.
        Given a council name, generate a concise, professional description (1-2 sentences, under 200 chars)
        that explains what the council does and how it helps users.
        
        Return ONLY the description text, no quotes or commentary.
      PROMPT
      output_format: :text
    },
    
    conversation: {
      fields: [:title, :initial_message],
      system_prompt: <<~PROMPT,
        You are an expert at starting productive AI conversations.
        Given a topic/concept, generate:
  1. title: Concise conversation title (under 60 chars)
        2. initial_message: Opening message that frames the discussion (2-3 sentences)
        
        Return ONLY valid JSON with these exact keys.
      PROMPT
      output_format: :json
    }
  }

  def self.generate(profile:, context:, account:)
    new(profile: profile, context: context, account: account).generate
  end

  def generate
    # 1. Validate profile
    # 2. Find suitable model
    # 3. Build prompt with profile's system prompt
    # 4. Call AI API
    # 5. Parse response (JSON or text based on profile)
    # 6. Return hash with generated fields
  end
end
```

## Usage Examples

```ruby
# Generate advisor profile
AIGenerator.generate(
  profile: :advisor,
  context: "A financial expert who helps with retirement planning",
  account: Current.account
)
# => { name: "Retirement Advisor", short_description: "Expert in retirement planning", system_prompt: "..." }

# Generate council description
AIGenerator.generate(
  profile: :council,
  context: "Engineering Leadership Council",
  account: Current.account
)
# => { description: "A council of experienced engineering leaders..." }

# Generate conversation starter
AIGenerator.generate(
  profile: :conversation,
  context: "How to improve our deployment pipeline",
  account: Current.account
)
# => { title: "Deployment Pipeline Optimization", initial_message: "..." }
```

## Controller Updates

### Single Endpoint Approach

```ruby
# app/controllers/ai_generations_controller.rb (new)
class AiGenerationsController < ApplicationController
  def create
    profile = params[:profile]&.to_sym
    context = params[:context]
    
    unless AIGenerator::PROFILES.key?(profile)
      render json: { error: "Unknown profile: #{profile}" }, status: :bad_request
      return
    end
    
    if context.blank?
      render json: { error: "Context is required" }, status: :unprocessable_entity
      return
    end
    
    begin
      result = AIGenerator.generate(
        profile: profile,
        context: context,
        account: Current.account
      )
      render json: result
    rescue AIGenerator::NoModelError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue AIGenerator::GenerationError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
```

**Routes:**
```ruby
# config/routes.rb
resource :ai_generation, only: [:create]
# POST /ai_generation
```

### Multiple Endpoint Approach (keep existing routes)

```ruby
# AdvisorsController
class AdvisorsController < ApplicationController
  def generate_content
    concept = params[:concept]
    
    begin
      result = AIGenerator.generate(
        profile: :advisor,
        context: concept,
        account: Current.account
      )
      render json: result
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end

# CouncilsController  
class CouncilsController < ApplicationController
  def generate_description
    name = params[:name]
    
    begin
      result = AIGenerator.generate(
        profile: :council,
        context: name,
        account: Current.account
      )
      render json: { description: result[:description] }  # Backward compatible
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
```

## Frontend Updates

### Stimulus Controller

```javascript
// app/javascript/controllers/ai_generator_controller.js
export default class extends Controller {
  static targets = [
    "modal",
    "contextInput",
    "errorMessage",
    "generateButton",
    "loadingIndicator",
    // Dynamic field targets based on profile
    "nameField",
    "shortDescriptionField", 
    "systemPromptField",
    "descriptionField",
    "titleField",
    "initialMessageField"
  ]

  static values = {
    url: String,
    profile: String  // 'advisor', 'council', 'conversation'
  }

  async generate(event) {
    event.preventDefault()
    
    const context = this.contextInputTarget.value.trim()
    if (!context) {
      this.showError("Please describe what you want to create")
      return
    }
    
    this.setLoading(true)
    
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          profile: this.profileValue,
          context: context
        })
      })
      
      const result = await response.json()
      
      if (response.ok) {
        this.populateFields(result)
        this.closeModal()
      } else {
        this.showError(result.error || "Generation failed")
      }
    } catch (error) {
      this.showError("An unexpected error occurred")
    } finally {
      this.setLoading(false)
    }
  }
  
  populateFields(result) {
    // Profile-specific field population
    switch(this.profileValue) {
      case 'advisor':
        if (this.hasNameFieldTarget) this.nameFieldTarget.value = result.name
        if (this.hasShortDescriptionFieldTarget) this.shortDescriptionFieldTarget.value = result.short_description
        if (this.hasSystemPromptFieldTarget) this.systemPromptFieldTarget.value = result.system_prompt
        break
      case 'council':
        if (this.hasDescriptionFieldTarget) this.descriptionFieldTarget.value = result.description
        break
      case 'conversation':
        if (this.hasTitleFieldTarget) this.titleFieldTarget.value = result.title
        if (this.hasInitialMessageFieldTarget) this.initialMessageFieldTarget.value = result.initial_message
        break
    }
  }
}
```

### Form Usage

```erb
<%# Advisor Form %>
<div data-controller="ai-generator"
     data-ai-generator-profile-value="advisor"
     data-ai-generator-url-value="<%= generate_content_space_advisors_path(space) %>">
  
  <%= form.text_field :name, data: { "ai-generator-target": "nameField" } %>
  <%= form.text_field :short_description, data: { "ai-generator-target": "shortDescriptionField" } %>
  <%= form.text_area :system_prompt, data: { "ai-generator-target": "systemPromptField" } %>
  <%= form.select :llm_model_id, ... %> <%# Manual selection %>
  
  <button type="button" data-action="click->ai-generator#openModal">
    Generate with AI
  </button>
  
  <%# Modal %>
  <dialog data-ai-generator-target="modal">
    <h3>Create Advisor with AI</h3>
    <textarea data-ai-generator-target="contextInput" 
              placeholder="Describe the advisor's role..."></textarea>
    <button data-action="click->ai-generator#generate">Generate</button>
  </dialog>
</div>

<%# Council Form %>
<div data-controller="ai-generator"
     data-ai-generator-profile-value="council"
     data-ai-generator-url-value="<%= generate_description_council_path(council) %>">
  
  <%= form.text_field :name %>
  <%= form.text_area :description, data: { "ai-generator-target": "descriptionField" } %>
  
  <button type="button" data-action="click->ai-generator#openModal">
    Generate with AI
  </button>
  
  <%# Modal %>
  <dialog data-ai-generator-target="modal">
    <h3>Generate Description</h3>
    <p>The AI will generate a description based on the council name.</p>
    <button data-action="click->ai-generator#generate">Generate</button>
  </dialog>
</div>
```

## Benefits

1. **Single Source of Truth** - One service handles all AI generation
2. **Consistent Interface** - Same pattern for all generation types
3. **Easy to Extend** - Add new profiles without changing core logic
4. **Testable** - Profile configs can be tested separately from generation logic
5. **DRY** - Shared model selection, error handling, API calling

## Migration Strategy

1. **Phase 1:** Create `AIGenerator` service with `advisor` and `council` profiles
2. **Phase 2:** Update controllers to use new service (keep old endpoints)
3. **Phase 3:** Create new unified Stimulus controller
4. **Phase 4:** Update frontend forms to use new controller
5. **Phase 5:** Remove old `PromptGenerator` and `DescriptionGenerator`

## Implementation Order

1. Create `AIGenerator` service with config-based profiles
2. Write comprehensive tests
3. Update `AdvisorsController` to use new service
4. Update `CouncilsController` to use new service  
5. Create new `ai_generator_controller.js` Stimulus controller
6. Update advisor form with modal and new controller
7. Update council form (regression test)
8. Remove old services and tests

## Open Questions

1. **Profile naming:** Use symbols (:advisor) or strings ("advisor")?
2. **Endpoint design:** Single `/ai_generation` endpoint or keep separate endpoints per context?
3. **Error format:** Standardize error responses across all profiles?
4. **Model selection:** All profiles use same model selection logic, or profile-specific?
5. **Caching:** Cache generated content per profile+context hash?
