import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { liability: Boolean }

  connect() {
    this.format()
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
  }

  unformat() {
    const value = this.element.value
    if (value === "" || value === null) return

    this.element.value = value.replace(/[-']/g, "")
  }
}
