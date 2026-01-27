import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { liability: Boolean, original: String, formula: String }

  connect() {
    this.element.classList.add("currency-input")
    // Check if this input is in the last column (has copy arrow)
    this.hasCopyArrow = this.element.dataset.copyPreviousTarget === "destination"
    // Store formula separately so we can restore it
    this.currentFormula = this.formulaValue || null
    if (this.currentFormula) {
      this.addFormulaIndicator()
    }
    this.format()
    this.checkModified()
  }

  addFormulaIndicator() {
    this.element.parentElement.classList.add("has-formula")
    if (this.hasCopyArrow) {
      this.element.parentElement.classList.add("has-copy-arrow")
    }
  }

  removeFormulaIndicator() {
    this.element.parentElement.classList.remove("has-formula", "has-copy-arrow")
  }

  format() {
    const rawValue = this.element.value
    if (rawValue === "" || rawValue === null) {
      // Clear formula indicator if value is empty
      this.currentFormula = null
      delete this.element.dataset.formula
      this.removeFormulaIndicator()
      return
    }

    // Check if this looks like a formula (contains operators)
    if (this.isFormula(rawValue)) {
      const result = this.evaluateFormula(rawValue)
      if (result !== null) {
        this.currentFormula = rawValue
        this.element.dataset.formula = rawValue
        this.addFormulaIndicator()
        this.displayValue(result)
        this.clearError()
      } else {
        // Invalid formula - mark as error
        this.markError()
        return
      }
    } else {
      // Plain number - clear any formula
      this.currentFormula = null
      delete this.element.dataset.formula
      this.removeFormulaIndicator()
      const num = parseFloat(rawValue.replace(/[-']/g, ""))
      if (!isNaN(num)) {
        this.displayValue(num)
      }
      this.clearError()
    }

    this.checkModified()
  }

  unformat() {
    // On focus, show the formula if present, otherwise show raw number
    if (this.currentFormula) {
      this.element.value = this.currentFormula
    } else {
      const value = this.element.value
      if (value !== "" && value !== null) {
        this.element.value = value.replace(/[-']/g, "")
      }
    }
  }

  isFormula(value) {
    // Contains operators beyond just a number (but not just a negative sign at start)
    const withoutLeadingMinus = value.replace(/^-/, "")
    return /[+\-*/()]/.test(withoutLeadingMinus)
  }

  evaluateFormula(formula) {
    // Sanitize: only allow digits, operators, parentheses, decimals, spaces
    const sanitized = formula.replace(/\s/g, "")
    if (!/^[\d+\-*/().]+$/.test(sanitized)) {
      return null
    }

    // Check for balanced parentheses
    let depth = 0
    for (const char of sanitized) {
      if (char === "(") depth++
      if (char === ")") depth--
      if (depth < 0) return null
    }
    if (depth !== 0) return null

    try {
      // Use Function constructor for safe eval (only math)
      const result = new Function(`return (${sanitized})`)()
      if (typeof result !== "number" || !isFinite(result)) {
        return null
      }
      return result
    } catch (e) {
      return null
    }
  }

  displayValue(num) {
    // Round to integer and format with thousand separators
    const rounded = Math.round(num)
    const formatted = rounded.toString().replace(/\B(?=(\d{3})+(?!\d))/g, "'")
    this.element.value = this.liabilityValue ? "-" + formatted : formatted
  }

  markError() {
    this.element.classList.add("border-red-400", "bg-red-50")
    this.element.classList.remove("border-slate-300", "border-amber-400", "bg-amber-50")
  }

  clearError() {
    this.element.classList.remove("border-red-400", "bg-red-50")
  }

  checkModified() {
    // Compare current formula or value against original
    const currentFormula = this.currentFormula
    const originalFormula = this.formulaValue || null

    let isModified = false

    if (currentFormula !== originalFormula) {
      // Formula changed
      isModified = true
    } else {
      // Compare numeric values
      const currentRaw = this.element.value.replace(/[-']/g, "")
      const originalRaw = (this.originalValue || "").replace(/[-']/g, "")
      const current = parseFloat(currentRaw) || 0
      const original = parseFloat(originalRaw) || 0
      const epsilon = 0.001
      isModified = Math.abs(current - original) > epsilon
    }

    if (isModified) {
      this.element.classList.add("border-amber-400", "bg-amber-50")
      this.element.classList.remove("border-slate-300")
    } else {
      this.element.classList.remove("border-amber-400", "bg-amber-50")
      this.element.classList.add("border-slate-300")
    }
  }
}
