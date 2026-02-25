import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "toggle"]
  static values = {
    expanded: { type: Boolean, default: false },
    maxLength: { type: Number, default: 500 }
  }

  connect() {
    this.updateDisplay()
  }

  toggle() {
    this.expandedValue = !this.expandedValue
    this.updateDisplay()
  }

  updateDisplay() {
    const content = this.contentTarget
    const fullText = content.dataset.fullText || content.textContent

    // Store full text if not already stored
    if (!content.dataset.fullText) {
      content.dataset.fullText = fullText
    }

    if (this.expandedValue) {
      // Show full text
      content.textContent = fullText
      this.toggleTarget.textContent = "Show less"
    } else {
      // Show truncated text
      if (fullText.length > this.maxLengthValue) {
        const truncated = fullText.substring(0, this.maxLengthValue) + "..."
        content.textContent = truncated
        this.toggleTarget.classList.remove("hidden")
      } else {
        // Text is short enough, no need for toggle
        content.textContent = fullText
        this.toggleTarget.classList.add("hidden")
      }
    }
  }
}
