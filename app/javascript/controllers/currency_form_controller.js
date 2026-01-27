import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  unformatAll(event) {
    this.inputTargets.forEach(input => {
      // If there's a formula, store the computed value for submission
      // but keep formula in a hidden field for server to read
      const formula = input.dataset.formula
      if (formula) {
        // Evaluate and set numeric value
        const result = this.evaluateFormula(formula)
        if (result !== null) {
          input.value = result.toString()
          // Add hidden input for formula - append to form to ensure it's submitted
          const formulaInput = document.createElement("input")
          formulaInput.type = "hidden"
          formulaInput.name = input.name.replace(/\]$/, "_formula]")
          formulaInput.value = formula
          this.element.appendChild(formulaInput)
        }
      } else {
        // Regular unformat - remove everything except digits and decimal point
        const value = input.value
        if (value) {
          input.value = value.replace(/[^\d.]/g, "")
        }
      }
    })
  }

  evaluateFormula(formula) {
    const sanitized = formula.replace(/\s/g, "")
    if (!/^[\d+\-*/().]+$/.test(sanitized)) return null
    try {
      const result = new Function(`return (${sanitized})`)()
      return typeof result === "number" && isFinite(result) ? result : null
    } catch (e) {
      return null
    }
  }
}
