import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="collapsible"
// Supports multiple content targets that are all toggled together
export default class extends Controller {
  static targets = ["content", "icon"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    this.render()
  }

  toggle(event) {
    // Prevent click from bubbling (e.g., if clicking on a cell in the row)
    event.stopPropagation()
    this.openValue = !this.openValue
    this.render()
  }

  render() {
    // Toggle all content targets
    this.contentTargets.forEach(el => {
      el.classList.toggle("hidden", !this.openValue)
    })
    
    // Update icon if present
    if (this.hasIconTarget) {
      this.iconTarget.textContent = this.openValue ? "▼" : "▶"
    }
  }
}
