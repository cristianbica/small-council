import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["apiKey", "organizationId", "saveButton", "testButton", "status", "statusText", "modelsList"]
  static values = { providerType: String }

  connect() {
    this.setUnverifiedState()
  }

  markDirty() {
    this.setUnverifiedState()
  }

  async testConnection() {
    const apiKey = this.apiKeyTarget.value.trim()

    if (apiKey.length === 0) {
      this.showError("API key is required.")
      return
    }

    this.testButtonTarget.disabled = true
    this.testButtonTarget.classList.add("loading")
    this.testButtonTarget.classList.add("loading-spinner")

    try {
      const response = await fetch("/providers/test_connection", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify({
          provider_type: this.providerTypeValue,
          api_key: apiKey,
          organization_id: this.organizationIdValue()
        })
      })

      const result = await response.json()

      if (response.ok && result.success) {
        this.showSuccess(result.models || [])
      } else {
        this.showError(result.error || "Connection failed. Please verify your credentials.")
      }
    } catch (error) {
      this.showError("Connection test failed. Please try again.")
    } finally {
      this.testButtonTarget.disabled = false
      this.testButtonTarget.classList.remove("loading")
      this.testButtonTarget.classList.remove("loading-spinner")
    }
  }

  setUnverifiedState() {
    this.saveButtonTarget.disabled = true
    this.statusTarget.classList.add("hidden")
    this.statusTarget.classList.remove("alert-success")
    this.statusTarget.classList.remove("alert-error")
    this.modelsListTarget.classList.add("hidden")
    this.modelsListTarget.innerHTML = ""
  }

  showSuccess(models) {
    this.saveButtonTarget.disabled = false
    this.statusTarget.classList.remove("hidden")
    this.statusTarget.classList.remove("alert-error")
    this.statusTarget.classList.add("alert-success")
    this.statusTextTarget.textContent = "Connection successful. You can now create this provider."

    if (models.length > 0) {
      const items = models.slice(0, 8).map((model) => `<li>${this.escapeHtml(model)}</li>`).join("")
      const extraCount = models.length - 8
      const extra = extraCount > 0 ? `<li>...and ${extraCount} more</li>` : ""
      this.modelsListTarget.innerHTML = items + extra
      this.modelsListTarget.classList.remove("hidden")
    } else {
      this.modelsListTarget.classList.add("hidden")
      this.modelsListTarget.innerHTML = ""
    }
  }

  showError(message) {
    this.saveButtonTarget.disabled = true
    this.statusTarget.classList.remove("hidden")
    this.statusTarget.classList.remove("alert-success")
    this.statusTarget.classList.add("alert-error")
    this.statusTextTarget.textContent = message
    this.modelsListTarget.classList.add("hidden")
    this.modelsListTarget.innerHTML = ""
  }

  organizationIdValue() {
    if (!this.hasOrganizationIdTarget) {
      return null
    }

    const value = this.organizationIdTarget.value.trim()
    return value.length > 0 ? value : null
  }

  csrfToken() {
    const token = document.querySelector("meta[name='csrf-token']")
    return token ? token.content : ""
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
