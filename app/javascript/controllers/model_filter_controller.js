import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["model", "searchInput", "freeToggle", "noResults"]
  static values = {
    totalCount: Number
  }

  connect() {
    console.log("ModelFilterController connected", {
      hasModelTarget: this.hasModelTarget,
      modelCount: this.modelTargets?.length,
      hasSearchInput: this.hasSearchInputTarget,
      hasFreeToggle: this.hasFreeToggleTarget,
      hasNoResults: this.hasNoResultsTarget
    })
    
    // Delay initial filter to ensure DOM is fully loaded
    requestAnimationFrame(() => {
      this.filter()
    })
  }

  filter() {
    console.log("Filter called", {
      searchInput: this.hasSearchInputTarget ? this.searchInputTarget?.value : "no target",
      freeToggle: this.hasFreeToggleTarget ? this.freeToggleTarget?.checked : "no target",
      modelCount: this.hasModelTarget ? this.modelTargets.length : 0
    })
    
    const searchTerm = (this.searchInputTarget?.value || "").toLowerCase()
    const showFreeOnly = this.freeToggleTarget?.checked || false
    let visibleCount = 0

    if (!this.hasModelTarget) {
      console.warn("No model targets found")
      return
    }

    this.modelTargets.forEach((model, index) => {
      const name = (model.dataset.modelName || "").toLowerCase()
      const id = (model.dataset.modelId || "").toLowerCase()
      const isFree = model.dataset.modelFree === "true"

      // Check text match
      const textMatch = name.includes(searchTerm) || id.includes(searchTerm)

      // Check free filter
      const freeMatch = !showFreeOnly || isFree

      // Show/hide based on both filters
      if (textMatch && freeMatch) {
        model.classList.remove("hidden")
        visibleCount++
      } else {
        model.classList.add("hidden")
      }
    })

    console.log("Filter complete", { visibleCount, totalCount: this.modelTargets.length })

    // Show/hide no results message
    if (visibleCount === 0 && this.hasNoResultsTarget) {
      this.noResultsTarget.classList.remove("hidden")
    } else if (this.hasNoResultsTarget) {
      this.noResultsTarget.classList.add("hidden")
    }

    // Update count display if it exists
    const countElement = this.element.querySelector("[data-filter-count]")
    if (countElement) {
      countElement.textContent = `${visibleCount} of ${this.totalCountValue} models`
    }
  }

  reset() {
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = ""
    }
    if (this.hasFreeToggleTarget) {
      this.freeToggleTarget.checked = false
    }
    this.filter()
  }
}
