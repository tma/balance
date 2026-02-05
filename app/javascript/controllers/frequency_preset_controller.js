import { Controller } from "@hotwired/stimulus"

// Connects the frequency preset dropdown to the days input field.
// Selecting a preset fills the input; selecting "Not tracked" clears it.
// Typing a custom value in the input updates the preset to show no match.
export default class extends Controller {
  static targets = ["input", "preset"]

  selectPreset() {
    const value = this.presetTarget.value
    if (value === "") {
      this.inputTarget.value = ""
    } else {
      this.inputTarget.value = value
    }
  }

  syncPreset() {
    const days = this.inputTarget.value
    const options = Array.from(this.presetTarget.options)
    const match = options.find(opt => opt.value === days)
    this.presetTarget.value = match ? days : ""
  }
}
