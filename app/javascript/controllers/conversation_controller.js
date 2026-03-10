import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messagesContainer", "textarea", "scrollButton", "charCount"]
  static values = {
    maxLength: { type: Number, default: 4000 }
  }

  connect() {
    console.log("[ConversationController] Connected")
    this.scrollToBottom()
    this.autoExpand()
    this.isAtBottom = true
    this.updateScrollPosition()
    this.updateCharCount()

    // Bind scroll event listener
    if (this.hasMessagesContainerTarget) {
      this.messagesContainerTarget.addEventListener("scroll", () => this.updateScrollPosition())
    }
  }

  disconnect() {
    if (this.hasMessagesContainerTarget) {
      this.messagesContainerTarget.removeEventListener("scroll", () => this.updateScrollPosition())
    }
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

    // Update character count
    this.updateCharCount()
  }

  // Update character counter
  updateCharCount() {
    if (!this.hasCharCountTarget || !this.hasTextareaTarget) return

    const length = this.textareaTarget.value.length
    const max = this.maxLengthValue
    this.charCountTarget.textContent = `${length} / ${max}`

    // Visual feedback if near limit
    if (length > max * 0.9) {
      this.charCountTarget.classList.add("text-error")
      this.charCountTarget.classList.remove("text-base-content/50")
    } else if (length > max * 0.8) {
      this.charCountTarget.classList.add("text-warning")
      this.charCountTarget.classList.remove("text-base-content/50", "text-error")
    } else {
      this.charCountTarget.classList.remove("text-error", "text-warning")
      this.charCountTarget.classList.add("text-base-content/50")
    }
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

  handleSubmitEnd(event) {
    if (!event.detail.success) {
      return
    }

    event.target.reset()
    this.autoExpand()
    this.updateCharCount()
  }

  // Scroll messages container to bottom
  scrollToBottom() {
    if (this.hasMessagesContainerTarget) {
      const container = this.messagesContainerTarget
      container.scrollTop = container.scrollHeight
      this.isAtBottom = true
      this.hideScrollButton()
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
    const wasAtBottom = this.isAtBottom
    this.isAtBottom = distanceFromBottom <= threshold

    // Show/hide scroll button based on position
    if (!this.isAtBottom) {
      this.showScrollButton()
    } else {
      this.hideScrollButton()
    }
  }

  // Show scroll-to-latest button
  showScrollButton() {
    if (this.hasScrollButtonTarget) {
      this.scrollButtonTarget.classList.remove("hidden")
    }
  }

  // Hide scroll-to-latest button
  hideScrollButton() {
    if (this.hasScrollButtonTarget) {
      this.scrollButtonTarget.classList.add("hidden")
    }
  }

  // Called after Turbo stream renders a new message
  messageRendered() {
    if (this.isAtBottom) {
      this.scrollToBottom()
    } else {
      // If not at bottom, show the scroll button to indicate new content
      this.showScrollButton()
    }
  }
}
