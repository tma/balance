import { Controller } from "@hotwired/stimulus"

// Manages privacy mode toggle - blurs all currency values
// Persists to sessionStorage (clears when tab closes)
export default class extends Controller {
  static targets = ["icon"]

  connect() {
    this.applyState()
    document.addEventListener("turbo:load", this.boundApplyState = this.applyState.bind(this))
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.boundApplyState)
  }

  toggle() {
    const isActive = sessionStorage.getItem("privacyMode") === "true"
    sessionStorage.setItem("privacyMode", !isActive)
    this.applyState()
  }

  applyState() {
    const isActive = sessionStorage.getItem("privacyMode") === "true"
    document.body.classList.toggle("privacy-mode", isActive)
    this.iconTargets.forEach(icon => {
      icon.textContent = isActive ? "◉" : "◎"
    })
  }
}
