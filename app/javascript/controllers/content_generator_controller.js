import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "modal",
    "conceptInput",
    "errorMessage",
    "generateButton",
    "loadingIndicator",
    // Field targets for different profiles
    "nameField",
    "shortDescriptionField",
    "systemPromptField",
    "descriptionField",
    "titleField",
    "initialMessageField"
  ]

  static values = {
    url: String,
    profile: String
  }

  connect() {
    console.log("[ContentGenerator] Connected, profile:", this.profileValue, "URL:", this.urlValue)
    this.isGenerating = false
  }

  openModal() {
    if (!this.hasModalTarget) {
      console.log("[ContentGenerator] No modal target, generating directly")
      // If no modal, we might be in direct mode - do nothing here
      return
    }

    console.log("[ContentGenerator] Opening modal")

    // Pre-fill concept if name field has value
    if (this.hasConceptInputTarget && this.hasNameFieldTarget && this.nameFieldTarget.value) {
      this.conceptInputTarget.value = this.nameFieldTarget.value
    }

    this.modalTarget.showModal()
    if (this.hasConceptInputTarget) {
      this.conceptInputTarget.focus()
    }
  }

  closeModal() {
    if (this.hasModalTarget) {
      console.log("[ContentGenerator] Closing modal")
      this.modalTarget.close()
      this.clearError()
    }
  }

  async generate(event) {
    event.preventDefault()
    console.log("[ContentGenerator] Generating for profile:", this.profileValue)

    if (this.isGenerating) return

    // Get concept from appropriate source
    let concept
    if (this.hasConceptInputTarget) {
      concept = this.conceptInputTarget.value.trim()
    } else if (this.profileValue === "council" && this.hasDescriptionFieldTarget) {
      // For council, if no modal, we might use the name field
      concept = this.element.querySelector('input[name*="[name]"]')?.value?.trim()
    }

    if (!concept) {
      this.showError("Please describe what you want to create")
      return
    }

    this.isGenerating = true
    this.setLoadingState(true)
    this.clearError()

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        body: JSON.stringify({
          profile: this.profileValue,
          concept: concept
        })
      })

      const result = await response.json()
      console.log("[ContentGenerator] Response:", result)

      if (response.ok) {
        this.populateFields(result)
        this.closeModal()
      } else {
        this.showError(result.error || "Failed to generate")
      }
    } catch (error) {
      console.error("[ContentGenerator] Error:", error)
      this.showError("An unexpected error occurred. Please try again.")
    } finally {
      this.isGenerating = false
      this.setLoadingState(false)
    }
  }

  populateFields(result) {
    console.log("[ContentGenerator] Populating fields for profile:", this.profileValue, "with:", result)

    switch (this.profileValue) {
      case "advisor":
        this.populateAdvisorFields(result)
        break
      case "council":
        this.populateCouncilFields(result)
        break
      case "conversation":
        this.populateConversationFields(result)
        break
      default:
        console.warn("[ContentGenerator] Unknown profile:", this.profileValue)
    }
  }

  populateAdvisorFields(result) {
    if (this.hasNameFieldTarget && result.name) {
      this.nameFieldTarget.value = result.name
    }
    if (this.hasShortDescriptionFieldTarget && result.short_description) {
      this.shortDescriptionFieldTarget.value = result.short_description
    }
    if (this.hasSystemPromptFieldTarget && result.system_prompt) {
      this.systemPromptFieldTarget.value = result.system_prompt
    }
  }

  populateCouncilFields(result) {
    if (this.hasNameFieldTarget && result.name) {
      this.nameFieldTarget.value = result.name
    }
    if (this.hasDescriptionFieldTarget && result.description) {
      this.descriptionFieldTarget.value = result.description
    }
  }

  populateConversationFields(result) {
    if (this.hasTitleFieldTarget && result.title) {
      this.titleFieldTarget.value = result.title
    }
    if (this.hasInitialMessageFieldTarget && result.initial_message) {
      this.initialMessageFieldTarget.value = result.initial_message
    }
  }

  setLoadingState(loading) {
    if (!this.hasGenerateButtonTarget) return

    if (loading) {
      this.generateButtonTarget.disabled = true
      this.generateButtonTarget.classList.add("loading")
      if (this.hasLoadingIndicatorTarget) {
        this.loadingIndicatorTarget.classList.remove("hidden")
      }
    } else {
      this.generateButtonTarget.disabled = false
      this.generateButtonTarget.classList.remove("loading")
      if (this.hasLoadingIndicatorTarget) {
        this.loadingIndicatorTarget.classList.add("hidden")
      }
    }
  }

  showError(message) {
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.textContent = message
      this.errorMessageTarget.classList.remove("hidden")
    } else {
      console.error("[ContentGenerator] Error:", message)
      alert(message)
    }
  }

  clearError() {
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.textContent = ""
      this.errorMessageTarget.classList.add("hidden")
    }
  }

  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }

  // Close modal when clicking outside
  clickOutside(event) {
    if (this.hasModalTarget && event.target === this.modalTarget) {
      this.closeModal()
    }
  }
}
