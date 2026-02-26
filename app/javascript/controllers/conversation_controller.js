import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messagesContainer", "textarea"]

  connect() {
    console.log("[ConversationController] Connected")
    this.scrollToBottom()
  }

  // Handle Ctrl+Enter to submit form
  submitOnCtrlEnter(event) {
    if (event.ctrlKey && event.key === "Enter") {
      event.preventDefault()
      const form = this.textareaTarget.closest("form")
      if (form) {
        form.requestSubmit()
      }
    }
  }

  // Scroll messages container to bottom
  scrollToBottom() {
    if (this.hasMessagesContainerTarget) {
      const container = this.messagesContainerTarget
      container.scrollTop = container.scrollHeight
    }
  }

  // Called after Turbo stream renders a new message
  messageRendered() {
    this.scrollToBottom()
  }
}
