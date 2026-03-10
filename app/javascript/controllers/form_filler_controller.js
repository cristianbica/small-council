import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fillable", "modal", "result"]

  static values = {
    url: String
  }

  modalTargetConnected(element) {
    if (!element.open) {
      element.showModal()
    }
  }

  handleDialogClose() {
    this.modalTarget.remove()
  }

  resultTargetConnected(element) {
    console.log(element.dataset)
    console.log(this.fillableTargets)
    const state = element.dataset.formFillerState

    if (state === "success") {
      this.applyPayload(this.parsePayload(element.dataset.payload))
      this.handleDialogClose()
    } else if (state === "error") {
      window.alert(element.dataset.error || "Unable to generate content right now.")
      this.handleDialogClose()
    }
  }

  applyPayload(payload) {
    this.fillableTargets.forEach((field) => {
      const attribute = field.dataset.formFillerAttribute

      if (!attribute || !(attribute in payload)) {
        return
      }

      field.value = payload[attribute]
      field.dispatchEvent(new Event("input", { bubbles: true }))
      field.dispatchEvent(new Event("change", { bubbles: true }))
    })
  }

  parsePayload(text) {
    try {
      return JSON.parse(text)
    } catch (error) {
      console.error("[FormFiller] Failed to parse payload", error)
      return {}
    }
  }
}
