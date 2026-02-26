import { Controller } from "@hotwired/stimulus"
import Tribute from "tributejs"

export default class extends Controller {
  static targets = ["input"]
  static values = {
    advisors: Array
  }

  connect() {
    console.log('Advisors data:', this.advisorsValue)
    
    const values = this.advisorsValue.map(advisor => ({
      value: this.parameterize(advisor.name)
    }))
    
    console.log('Tribute values:', values)

    this.tribute = new Tribute({
      trigger: '@',
      values: values,
      lookup: 'value',
      fillAttr: 'value',
      selectTemplate: (item) => `@${item.original.value} `,
      menuItemTemplate: (item) => `@${item.original.value}`,
      requireLeadingSpace: false,
      spaceSelectsMatch: false
    })

    this.tribute.attach(this.inputTarget)

    this.inputTarget.addEventListener('tribute-replaced', () => {
      this.inputTarget.dispatchEvent(new Event('input', { bubbles: true }))
    })
  }

  disconnect() {
    if (this.tribute) {
      this.tribute.detach(this.inputTarget)
    }
  }

  parameterize(string) {
    return string
      .toLowerCase()
      .replace(/[^a-z0-9\s-]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '')
  }
}
