import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "modal",
    "descriptionInput",
    "systemPromptField",
    "descriptionField",
    "generateButton",
    "loadingIndicator",
    "errorMessage",
    "advisorNameField",
    "councilNameField"
  ]

  static values = {
    url: String
  }

  connect() {
    console.log("[PromptGenerator] Controller connected, URL:", this.urlValue)
    this.isGenerating = false
  }

  openModal() {
    if (!this.hasModalTarget) {
      console.log("[PromptGenerator] No modal target found")
      return
    }
    
    console.log("[PromptGenerator] Opening modal")
    
    // Pre-fill input based on context (advisor or council)
    let prefillValue = ""
    
    if (this.hasAdvisorNameFieldTarget) {
      prefillValue = this.advisorNameFieldTarget.value
    } else if (this.hasCouncilNameFieldTarget) {
      prefillValue = this.councilNameFieldTarget.value
    }
    
    if (prefillValue && this.hasDescriptionInputTarget && !this.descriptionInputTarget.value) {
      this.descriptionInputTarget.value = prefillValue
    }

    this.modalTarget.showModal()
    if (this.hasDescriptionInputTarget) {
      this.descriptionInputTarget.focus()
    }
  }

  closeModal() {
    console.log("[PromptGenerator] Closing modal")
    this.modalTarget.close()
    this.clearError()
  }

  async generate(event) {
    event.preventDefault()
    console.log("[PromptGenerator] Generating")

    if (this.isGenerating) return

    // Determine input source: systemPromptField for advisor mode, descriptionInput for council mode
    const inputTarget = this.hasSystemPromptFieldTarget 
      ? this.systemPromptFieldTarget 
      : (this.hasDescriptionInputTarget ? this.descriptionInputTarget : null)
    
    if (!inputTarget) {
      this.showError("Input field not found")
      return
    }

    const inputValue = inputTarget.value.trim()
    if (!inputValue) {
      this.showError("Please enter a value")
      return
    }

    this.isGenerating = true
    this.setLoadingState(true)
    this.clearError()

    // Determine if this is for advisor prompt or council description
    const isAdvisorPrompt = this.hasSystemPromptFieldTarget
    const requestBody = isAdvisorPrompt 
      ? { description: inputValue }
      : { name: inputValue }

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        body: JSON.stringify(requestBody)
      })

      const result = await response.json()
      console.log("[PromptGenerator] Response:", result)

      if (response.ok) {
        // Handle both advisor prompt and council description responses
        const generatedContent = result.prompt || result.description
        if (generatedContent) {
          if (isAdvisorPrompt) {
            this.systemPromptFieldTarget.value = generatedContent
          } else if (this.hasDescriptionFieldTarget) {
            this.descriptionFieldTarget.value = generatedContent
          }
          // Only close modal if it exists (council mode)
          if (this.hasModalTarget) {
            this.closeModal()
          }
        } else {
          this.showError(result.error || "Failed to generate")
        }
      } else {
        this.showError(result.error || "Failed to generate")
      }
    } catch (error) {
      console.error("[PromptGenerator] Error:", error)
      this.showError("An unexpected error occurred. Please try again.")
    } finally {
      this.isGenerating = false
      this.setLoadingState(false)
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
      // Fallback to alert if no error message target
      console.error("[PromptGenerator] Error:", message)
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

  closeModal() {
    if (this.hasModalTarget) {
      console.log("[PromptGenerator] Closing modal")
      this.modalTarget.close()
      this.clearError()
    }
  }
}
