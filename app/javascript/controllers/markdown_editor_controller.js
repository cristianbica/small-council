import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview"]

  connect() {
    this.updatePreview()
  }

  updatePreview() {
    const markdown = this.inputTarget.value
    // Simple markdown to HTML conversion for preview
    // We'll do basic formatting: paragraphs, headers, lists, code, bold, italic
    let html = this.basicMarkdownToHtml(markdown)
    this.previewTarget.innerHTML = html
  }

  basicMarkdownToHtml(markdown) {
    if (!markdown) return "<p class=\"text-base-content/40 italic\">Preview will appear here...</p>"
    
    let html = markdown
    
    // Code blocks
    html = html.replace(/```(\w+)?\n([\s\S]*?)```/g, '<pre><code>$2</code></pre>')
    
    // Inline code
    html = html.replace(/`([^`]+)`/g, '<code class="bg-base-300 px-1 rounded">$1</code>')
    
    // Headers
    html = html.replace(/^### (.*$)/gim, '<h3 class="text-lg font-bold mt-4 mb-2">$1</h3>')
    html = html.replace(/^## (.*$)/gim, '<h2 class="text-xl font-bold mt-4 mb-2">$1</h2>')
    html = html.replace(/^# (.*$)/gim, '<h1 class="text-2xl font-bold mt-4 mb-2">$1</h1>')
    
    // Bold
    html = html.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
    
    // Italic
    html = html.replace(/\*(.*?)\*/g, '<em>$1</em>')
    
    // Links
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" class="link" target="_blank">$1</a>')
    
    // Lists
    html = html.replace(/^\s*-\s+(.*$)/gim, '<li class="ml-4">$1</li>')
    
    // Wrap in paragraphs
    html = html.split('\n\n').map(para => {
      if (para.trim().startsWith('<')) return para
      return `<p>${para}</p>`
    }).join('')
    
    return html
  }
}
