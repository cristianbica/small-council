import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messagesContainer", "textarea"]

  connect() {
    console.log("[ConversationController] Connected")
    this.scrollToBottom()
    this.autoExpand()
    this.isAtBottom = true
    this.updateScrollPosition()
  }

  // Auto-expand textarea as user types
  autoExpand() {
    const textarea = this.textareaTarget
    const minRows = 1
    const maxRows = 12

    // Reset to minimum to get accurate scrollHeight
    textarea.rows = minRows

    // Calculate required rows based on scrollHeight
    const computedStyle = getComputedStyle(textarea)
    const lineHeight = parseInt(computedStyle.lineHeight) || 24
    const padding = parseInt(computedStyle.paddingTop) + parseInt(computedStyle.paddingBottom)
    const contentHeight = textarea.scrollHeight - padding
    const newRows = Math.ceil(contentHeight / lineHeight)

    // Clamp between min and max
    textarea.rows = Math.max(minRows, Math.min(newRows, maxRows))
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

  // Track if user is near bottom of messages
  updateScrollPosition() {
    if (!this.hasMessagesContainerTarget) {
      this.isAtBottom = true
      return
    }

    const container = this.messagesContainerTarget
    const threshold = 40
    const distanceFromBottom = container.scrollHeight - container.scrollTop - container.clientHeight
    this.isAtBottom = distanceFromBottom <= threshold
  }

  // Called after Turbo stream renders a new message
  messageRendered() {
    if (this.isAtBottom) {
      this.scrollToBottom()
    }
  }
}
