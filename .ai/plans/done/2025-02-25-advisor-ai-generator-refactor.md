# Advisor AI Generator Refactoring Plan

## Overview
Refactor the "Generate with AI" functionality to generate complete advisor profiles (name, short description, system prompt) from a single concept description. Make the system extensible for different generation contexts (advisor, council, conversation).

## Changes Required

### 1. Backend - New Service: `AdvisorGenerator`

**File:** `app/services/advisor_generator.rb`

Create a new service that generates all three advisor fields from a concept:

```ruby
class AdvisorGenerator
  class Error < StandardError; end
  class NoModelError < Error; end
  class GenerationError < Error; end

  def self.generate(concept:, account:)
    new(concept: concept, account: account).generate
  end

  def generate
    # Returns: { name: "...", short_description: "...", system_prompt: "..." }
  end
end
```

**System Prompt:**
```
You are an expert at creating AI advisor profiles.
Given a concept/role description, generate:
1. A concise name (2-4 words, professional)
2. A brief short_description (under 100 characters, for lists)
3. A comprehensive system_prompt (2-4 paragraphs defining personality, expertise, tone)

Return ONLY a JSON object:
{
  "name": "...",
  "short_description": "...", 
  "system_prompt": "..."
}
```

### 2. Backend - Controller Update

**File:** `app/controllers/advisors_controller.rb`

Update `generate_prompt` action to use `AdvisorGenerator`:

```ruby
def generate_prompt
  concept = params[:concept]
  
  if concept.blank?
    render json: { error: "Concept is required" }, status: :unprocessable_entity
    return
  end

  begin
    result = AdvisorGenerator.generate(concept: concept, account: Current.account)
    render json: result  # { name, short_description, system_prompt }
  rescue AdvisorGenerator::NoModelError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue AdvisorGenerator::GenerationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
```

### 3. Frontend - Add Modal to Advisor Form

**File:** `app/views/advisors/_form.html.erb`

Add a modal similar to council form:

```erb
<%# Add at end of form, outside form element %>
<dialog data-prompt-generator-target="modal" class="modal">
  <div class="modal-box">
    <h3 class="font-bold text-lg mb-4">Generate Advisor with AI</h3>
    <p class="text-sm text-base-content/70 mb-4">
      Describe the advisor's role or expertise. The AI will suggest a name, short description, and system prompt.
    </p>
    
    <div class="form-control mb-4">
      <label class="label">
        <span class="label-text">Concept / Role Description</span>
      </label>
      <textarea data-prompt-generator-target="conceptInput"
                class="textarea textarea-bordered w-full"
                rows="3"
                placeholder="e.g., An expert financial advisor who helps with investment decisions and retirement planning"
                required></textarea>
    </div>

    <div data-prompt-generator-target="errorMessage" class="alert alert-error hidden mb-4">
      <svg>...</svg>
      <span></span>
    </div>

    <div class="modal-action">
      <button type="button" class="btn btn-ghost" data-action="click->prompt-generator#closeModal">
        Cancel
      </button>
      <button type="button" 
              data-prompt-generator-target="generateButton"
              data-action="click->prompt-generator#generate"
              class="btn btn-primary">
        <span data-prompt-generator-target="loadingIndicator" class="hidden loading loading-spinner loading-xs mr-2"></span>
        Generate Advisor
      </button>
    </div>
  </div>
</dialog>
```

### 4. Frontend - Update Form Fields

**File:** `app/views/advisors/_form.html.erb`

Add data attributes to all three fields:

```erb
<%= form.text_field :name,
    data: { "prompt-generator-target": "nameField" },
    ... %>

<%= form.text_field :short_description,
    data: { "prompt-generator-target": "shortDescriptionField" },
    ... %>

<%= form.text_area :system_prompt,
    data: { "prompt-generator-target": "systemPromptField" },
    ... %>
```

### 5. Frontend - Update Button

Change button to open modal:

```erb
<button type="button" 
        class="btn btn-outline btn-sm"
        data-action="click->prompt-generator#openModal">
  <svg>...</svg>
  Generate with AI
</button>
```

### 6. Frontend - Update Stimulus Controller

**File:** `app/javascript/controllers/prompt_generator_controller.js`

Add new targets and make controller context-aware:

```javascript
static targets = [
  "modal",
  "conceptInput",        // For advisor concept
  "descriptionInput",  // For council name (legacy)
  "nameField",          // Advisor name
  "shortDescriptionField", // Advisor short description
  "systemPromptField",  // Advisor system prompt
  "descriptionField",   // Council description (legacy)
  "advisorNameField",   // Legacy
  "councilNameField",   // Legacy
  "generateButton",
  "loadingIndicator",
  "errorMessage"
]

async generate(event) {
  // Determine mode based on which targets exist
  const isAdvisorMode = this.hasNameFieldTarget || this.hasSystemPromptFieldTarget
  const isCouncilMode = this.hasDescriptionFieldTarget
  
  // Get input value from appropriate source
  let inputValue
  if (this.hasConceptInputTarget && this.conceptInputTarget.value.trim()) {
    inputValue = this.conceptInputTarget.value.trim()
  } else if (this.hasDescriptionInputTarget) {
    inputValue = this.descriptionInputTarget.value.trim()
  }
  
  // Handle response based on mode
  if (isAdvisorMode) {
    this.nameFieldTarget.value = result.name
    this.shortDescriptionFieldTarget.value = result.short_description
    this.systemPromptFieldTarget.value = result.system_prompt
  } else if (isCouncilMode) {
    this.descriptionFieldTarget.value = result.description
  }
}
```

### 7. Future Extensibility

For conversation topics and other contexts, the pattern is:

1. Create new service (e.g., `TopicGenerator`)
2. Add new endpoint or extend existing
3. Add context-specific targets to form
4. Controller auto-detects mode by checking `hasXTarget`

## Testing

1. **Unit Tests:** Test `AdvisorGenerator` service with mocked LLM responses
2. **Integration Tests:** Test controller endpoint returns correct JSON structure
3. **System Tests:** Verify modal opens, generates, and fills all fields

## Migration Path

1. Create `AdvisorGenerator` service
2. Update controller to use new service
3. Update form with modal and data attributes
4. Update Stimulus controller with defensive checks
5. Verify council description generation still works (regression test)

## Estimated Time
- Service + Tests: 1-2 hours
- Controller updates: 30 minutes
- Frontend modal + form: 1 hour
- Controller refactor: 1-2 hours
- Testing: 30 minutes

**Total: 4-6 hours**

## Acceptance Criteria

- [ ] Clicking "Generate with AI" opens modal asking for concept
- [ ] AI generates name, short_description, and system_prompt
- [ ] All three fields are populated in the form
- [ ] User can edit generated content before saving
- [ ] Model selection remains manual (last field)
- [ ] Council description generation still works
- [ ] Error handling shows user-friendly messages
- [ ] Loading states work correctly
