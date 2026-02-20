import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["spinner"]

  loading() {
    // Show spinner
    this.spinnerTarget.classList.remove("hidden")
    
    // Disable the toggle while loading
    const checkbox = this.element.querySelector('input[type="checkbox"]')
    if (checkbox) {
      checkbox.disabled = true
    }
  }

  complete() {
    // Hide spinner
    this.spinnerTarget.classList.add("hidden")
    
    // Re-enable the toggle
    const checkbox = this.element.querySelector('input[type="checkbox"]')
    if (checkbox) {
      checkbox.disabled = false
    }
  }
}
