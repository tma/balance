import { Controller } from "@hotwired/stimulus"

// Copies the value from the previous month input to the current input
export default class extends Controller {
  static targets = ["source", "destination"]

  copy() {
    if (this.hasSourceTarget && this.hasDestinationTarget) {
      const sourceInput = this.sourceTarget
      const destInput = this.destinationTarget

      // Get the raw value (unformatted)
      let value = sourceInput.dataset.rawValue || sourceInput.value

      // Set the value
      destInput.value = value
      destInput.dataset.rawValue = value

      // Trigger format
      destInput.dispatchEvent(new Event('blur'))
    }
  }
}
