import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["description", "category", "badge"]
  static values = { url: String, userSelected: Boolean }

  connect() {
    this.userSelectedValue = false
    this.timeout = null
    this.abortController = null
  }

  suggest() {
    this.userSelectedValue = false
    clearTimeout(this.timeout)
    this.abortController?.abort()

    const description = this.descriptionTarget.value.trim()
    if (description.length < 3) return

    this.timeout = setTimeout(() => this.fetchSuggestion(description), 300)
  }

  manualSelect() {
    this.userSelectedValue = true
    this.hideBadge()
  }

  async fetchSuggestion(description) {
    this.abortController = new AbortController()
    const type = this.element.querySelector('[name*="transaction_type"]')?.value || "expense"

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({ description, transaction_type: type }),
        signal: this.abortController.signal
      })

      const data = await response.json()
      if (data.category_id && !this.userSelectedValue) {
        this.categoryTarget.value = data.category_id
        this.showBadge()
      }
    } catch (e) {
      if (e.name !== "AbortError") console.warn("Category suggestion failed:", e)
    }
  }

  showBadge() {
    if (this.hasBadgeTarget) this.badgeTarget.classList.remove("hidden")
  }

  hideBadge() {
    if (this.hasBadgeTarget) this.badgeTarget.classList.add("hidden")
  }
}
