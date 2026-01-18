import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { liability: Boolean, original: String }

  connect() {
    this.format()
    this.checkModified()
  }

  format() {
    const value = this.element.value
    if (value === "" || value === null) return

    const num = parseFloat(value.replace(/[-']/g, ""))
    if (!isNaN(num)) {
      // Format with ' as thousand separator
      const parts = num.toFixed(2).split(".")
      parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, "'")
      // Remove trailing zeros after decimal
      const decimal = parseFloat("0." + parts[1])
      const formatted = decimal > 0 ? parts.join(".") : parts[0]
      // Add minus prefix for liabilities
      this.element.value = this.liabilityValue ? "-" + formatted : formatted
    }

    this.checkModified()
  }

  unformat() {
    const value = this.element.value
    if (value === "" || value === null) return

    this.element.value = value.replace(/[-']/g, "")
  }

  checkModified() {
    const currentRaw = this.element.value.replace(/[-']/g, "")
    const originalRaw = (this.originalValue || "").replace(/[-']/g, "")
    
    // Compare numeric values (handle empty as 0)
    const current = parseFloat(currentRaw) || 0
    const original = parseFloat(originalRaw) || 0
    
    if (current !== original) {
      this.element.classList.add("border-amber-400", "bg-amber-50")
      this.element.classList.remove("border-slate-300")
    } else {
      this.element.classList.remove("border-amber-400", "bg-amber-50")
      this.element.classList.add("border-slate-300")
    }
  }
}
