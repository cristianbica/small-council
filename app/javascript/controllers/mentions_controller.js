import { Controller } from "@hotwired/stimulus"
import Tribute from "tributejs"

export default class extends Controller {
  static targets = ["input"]
  static values = {
    advisors: Array,
    commands: Array
  }

  inputTargetConnected() {
    const advisorValues = this.advisorsValue.map((advisor) => ({
      value: advisor.name
    }))

    const commandValues = this.commandsValue.map((command) => ({
      value: command.name,
      description: command.description
    }))

    this.tribute = new Tribute({
      collection: [
        {
          trigger: "@",
          values: advisorValues,
          lookup: "value",
          fillAttr: "value",
          selectTemplate: (item) => `@${item.original.value} `,
          menuItemTemplate: (item) => `@${item.original.value}`,
          requireLeadingSpace: false,
          spaceSelectsMatch: false
        },
        {
          trigger: "/",
          values: commandValues,
          lookup: "value",
          fillAttr: "value",
          selectTemplate: (item) => `/${item.original.value} `,
          menuItemTemplate: (item) => {
            const description = item.original.description || ""
            return `<div class=\"flex items-center justify-between gap-3\"><span>/${item.original.value}</span><span class=\"text-xs opacity-70\">${description}</span></div>`
          },
          requireLeadingSpace: false,
          spaceSelectsMatch: true,
          menuShowMinLength: 0
        }
      ]
    })

    this.tribute.attach(this.inputTarget)

    this.inputTarget.addEventListener("tribute-replaced", () => {
      this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    })
  }

  disconnect() {
    if (this.tribute) {
      this.tribute.detach(this.inputTarget)
    }
  }
}
