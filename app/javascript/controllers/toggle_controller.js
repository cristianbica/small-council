import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["spinner"]

  connect() {
    // Reset state when controller connects (after Turbo stream updates)
    this.reset()
  }

  loading() {
    // Show spinner
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("hidden")
    }
    
    // Disable the toggle while loading
    const checkbox = this.element.querySelector('input[type="checkbox"]')
    if (checkbox) {
      checkbox.disabled = true
    }
  }

  reset() {
    // Hide spinner
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("hidden")
    }
    
    // Re-enable the toggle
    const checkbox = this.element.querySelector('input[type="checkbox"]')
    if (checkbox) {
      checkbox.disabled = false
    }
  }
}
