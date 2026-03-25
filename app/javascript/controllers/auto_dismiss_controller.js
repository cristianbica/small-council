import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    delay: { type: Number, default: 5000 }
  }

  connect() {
    this.timeout = setTimeout(() => this.remove(), this.delayValue)
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  close() {
    this.remove()
  }

  remove() {
    this.element.remove()
  }
}
