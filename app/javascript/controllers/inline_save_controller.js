import { Controller } from "@hotwired/stimulus"

// Shows a save button when any inline input in the form is modified
// Works with currency-input controller by comparing raw numeric values
export default class extends Controller {
  static targets = ["input", "save"]

  connect() {
    this.originalValues = new Map()
    this.inputTargets.forEach(input => {
      // Store raw numeric value (strip formatting like ' thousands separator)
      this.originalValues.set(input, this.parseValue(input.value))
    })
  }

  check() {
    const modified = this.inputTargets.some(input => {
      const current = this.parseValue(input.value)
      const original = this.originalValues.get(input)
      // Use epsilon comparison for floating point
      return Math.abs(current - original) > 0.001
    })
    
    if (modified) {
      this.saveTarget.disabled = false
      this.saveTarget.classList.remove("text-slate-400")
      this.saveTarget.classList.add("text-cyan-600", "hover:text-cyan-700")
    } else {
      this.saveTarget.disabled = true
      this.saveTarget.classList.add("text-slate-400")
      this.saveTarget.classList.remove("text-cyan-600", "hover:text-cyan-700")
    }
  }

  unformatAll() {
    this.inputTargets.forEach(input => {
      if (input.value) {
        // Remove formatting characters, keep only digits and decimal point
        input.value = input.value.replace(/[^\d.]/g, "")
      }
    })
  }

  parseValue(value) {
    // Strip formatting characters (' for thousands, - for negatives)
    const raw = (value || "").replace(/[-']/g, "")
    return parseFloat(raw) || 0
  }
}
