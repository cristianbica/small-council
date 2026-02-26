import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages", "input", "sendButton", "loading", "suggestions"]
  static values = {
    spaceId: String
  }

  connect() {
    this.scrollToBottom()
    this.inputTarget.focus()
    this.autoExpand()
  }

  // Auto-expand textarea as user types
  autoExpand() {
    const textarea = this.inputTarget
    const minRows = 2
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

  // Send message when Enter is pressed (without Shift)
  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.send()
    }
  }

  // Send a quick suggestion message
  sendQuick(event) {
    const message = event.currentTarget.dataset.message
    this.inputTarget.value = message
    this.send()
  }

  // Send the user's message
  async send() {
    const message = this.inputTarget.value.trim()
    if (!message) return

    // Add user message to chat
    this.addMessage(message, "user")

    // Clear input
    this.inputTarget.value = ""

    // Show loading
    this.showLoading()

    try {
      // Send to server
      const response = await this.sendMessageToServer(message)

      // Add Scribe response
      this.addMessage(response.message, "scribe")

      // Handle tool calls if present
      if (response.tool_calls && response.tool_calls.length > 0) {
        this.handleToolCalls(response.tool_calls)
      }
    } catch (error) {
      this.addMessage("Sorry, I encountered an error. Please try again.", "scribe", true)
      console.error("Chat error:", error)
    } finally {
      this.hideLoading()
      this.scrollToBottom()
    }
  }

  // Send message to server
  async sendMessageToServer(message) {
    const response = await fetch(`/spaces/${this.spaceIdValue}/scribe/chat`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.getCSRFToken()
      },
      body: JSON.stringify({ message: message })
    })

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }

    return response.json()
  }

  // Add a message to the chat
  addMessage(content, sender, isError = false) {
    const messageDiv = document.createElement("div")
    messageDiv.className = "flex gap-3 animate-fade-in"

    if (sender === "user") {
      messageDiv.innerHTML = `
        <div class="flex-1 flex justify-end">
          <div class="bg-primary text-primary-content rounded-lg p-4 max-w-2xl">
            <p>${this.escapeHtml(content)}</p>
          </div>
        </div>
        <div class="w-8 h-8 rounded-full bg-base-300 flex items-center justify-center text-sm font-bold shrink-0">
          You
        </div>
      `
    } else {
      messageDiv.innerHTML = `
        <div class="w-8 h-8 rounded-full bg-primary flex items-center justify-center text-primary-content text-sm font-bold shrink-0">
          S
        </div>
        <div class="flex-1">
          <div class="bg-base-200 rounded-lg p-4 max-w-2xl ${isError ? 'border border-error' : ''}">
            <p class="${isError ? 'text-error' : ''}">${this.formatMessage(content)}</p>
          </div>
        </div>
      `
    }

    this.messagesTarget.appendChild(messageDiv)
    this.scrollToBottom()
  }

  // Handle tool calls from Scribe
  handleToolCalls(toolCalls) {
    toolCalls.forEach(toolCall => {
      // Show tool execution indicator
      this.addToolExecutionMessage(toolCall)

      // Execute the tool
      this.executeTool(toolCall)
    })
  }

  // Show tool execution in chat
  addToolExecutionMessage(toolCall) {
    const div = document.createElement("div")
    div.className = "flex gap-3 opacity-60"
    div.innerHTML = `
      <div class="w-8 h-8 rounded-full bg-accent flex items-center justify-center text-accent-content text-xs shrink-0">
        🔧
      </div>
      <div class="flex-1">
        <div class="bg-accent/10 rounded-lg p-3 max-w-2xl text-sm">
          <p>Executing: <strong>${this.escapeHtml(toolCall.name)}</strong></p>
        </div>
      </div>
    `
    this.messagesTarget.appendChild(div)
    this.scrollToBottom()
  }

  // Execute a tool
  async executeTool(toolCall) {
    try {
      const response = await fetch(`/spaces/${this.spaceIdValue}/scribe/execute_tool`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        },
        body: JSON.stringify({
          tool_name: toolCall.name,
          params: toolCall.arguments
        })
      })

      const result = await response.json()

      // Show tool result
      this.addToolResultMessage(toolCall.name, result)
    } catch (error) {
      console.error("Tool execution error:", error)
      this.addMessage(`Tool execution failed: ${error.message}`, "scribe", true)
    }
  }

  // Show tool result
  addToolResultMessage(toolName, result) {
    const div = document.createElement("div")
    div.className = "flex gap-3 ml-11"

    const success = result.success || !result.error
    const message = result.message || result.error || "Tool executed"

    div.innerHTML = `
      <div class="flex-1">
        <div class="bg-base-100 border border-base-300 rounded-lg p-3 max-w-xl text-sm">
          <p class="${success ? 'text-success' : 'text-error'}">
            ${success ? '✓' : '✗'} <strong>${this.escapeHtml(toolName)}:</strong> ${this.escapeHtml(message)}
          </p>
        </div>
      </div>
    `
    this.messagesTarget.appendChild(div)
    this.scrollToBottom()
  }

  // Show loading indicator
  showLoading() {
    this.loadingTarget.classList.remove("hidden")
    this.sendButtonTarget.disabled = true
    this.inputTarget.disabled = true
  }

  // Hide loading indicator
  hideLoading() {
    this.loadingTarget.classList.add("hidden")
    this.sendButtonTarget.disabled = false
    this.inputTarget.disabled = false
    this.inputTarget.focus()
  }

  // Scroll to bottom of messages
  scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  // Format message with simple markdown-like formatting
  formatMessage(content) {
    if (!content) return ""

    // Escape HTML
    let formatted = this.escapeHtml(content)

    // Convert **text** to bold
    formatted = formatted.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")

    // Convert *text* to italic
    formatted = formatted.replace(/\*(.+?)\*/g, "<em>$1</em>")

    // Convert `text` to code
    formatted = formatted.replace(/`(.+?)`/g, "<code class=\"bg-base-300 px-1 rounded text-sm\">$1</code>")

    // Convert newlines to breaks
    formatted = formatted.replace(/\n/g, "<br>")

    return formatted
  }

  // Escape HTML to prevent XSS
  escapeHtml(text) {
    if (!text) return ""
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  // Get CSRF token from meta tag
  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }
}
