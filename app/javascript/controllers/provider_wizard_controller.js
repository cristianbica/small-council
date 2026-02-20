import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["loading", "success", "error", "modelsList", "errorMessage"]
  static values = {
    providerType: String,
    apiKey: String,
    organizationId: String
  }

  connect() {
    this.testConnection()
  }

  async testConnection() {
    try {
      const response = await fetch("/providers/test_connection", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        body: JSON.stringify({
          provider_type: this.providerTypeValue,
          api_key: this.apiKeyValue,
          organization_id: this.organizationIdValue
        })
      })

      const result = await response.json()

      this.loadingTarget.classList.add("hidden")

      if (result.success) {
        this.showSuccess(result.models)
      } else {
        this.showError(result.error)
      }
    } catch (error) {
      this.loadingTarget.classList.add("hidden")
      this.showError("An unexpected error occurred. Please try again.")
    }
  }

  showSuccess(models) {
    this.successTarget.classList.remove("hidden")

    // Populate models list
    if (models && models.length > 0) {
      const modelsHtml = models.slice(0, 10).map(model => {
        return `<li class="flex items-center gap-2">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
          ${this.escapeHtml(model)}
        </li>`
      }).join("")

      const moreCount = models.length - 10
      const moreHtml = moreCount > 0 ? `<li class="text-base-content/50 italic">...and ${moreCount} more</li>` : ""

      this.modelsListTarget.innerHTML = modelsHtml + moreHtml
    } else {
      this.modelsListTarget.innerHTML = "<li class=\"text-base-content/50\">No models found</li>"
    }
  }

  showError(message) {
    this.errorTarget.classList.remove("hidden")
    this.errorMessageTarget.textContent = message || "Connection failed. Please check your API key and try again."
  }

  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
