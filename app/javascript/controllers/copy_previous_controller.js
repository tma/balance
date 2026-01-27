import { Controller } from "@hotwired/stimulus"

// Copies the value from the previous month input to the current input
export default class extends Controller {
  static targets = ["source", "destination"]

  copy() {
    if (this.hasSourceTarget && this.hasDestinationTarget) {
      const sourceInput = this.sourceTarget
      const destInput = this.destinationTarget

      // Check if source has a formula
      const sourceFormula = sourceInput.dataset.formula

      if (sourceFormula) {
        // Copy the formula - set it as the value so currency-input can process it
        destInput.value = sourceFormula
      } else {
        // Get the raw value (unformatted)
        let value = sourceInput.dataset.rawValue || sourceInput.value
        destInput.value = value
        destInput.dataset.rawValue = value
      }

      // Trigger blur to format and process formula
      destInput.dispatchEvent(new Event('blur'))
    }
  }
}
