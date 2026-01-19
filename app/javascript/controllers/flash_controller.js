import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    delay: { type: Number, default: 5000 }
  }

  connect() {
    this.timeout = setTimeout(() => {
      this.dismiss()
    }, this.delayValue)
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  dismiss() {
    // Animate collapse
    this.element.style.overflow = 'hidden'
    this.element.style.transition = 'max-height 0.3s ease-out, opacity 0.3s ease-out, margin 0.3s ease-out, padding 0.3s ease-out'
    this.element.style.maxHeight = this.element.scrollHeight + 'px'
    
    // Force reflow
    this.element.offsetHeight
    
    // Collapse
    this.element.style.maxHeight = '0'
    this.element.style.opacity = '0'
    this.element.style.marginTop = '0'
    this.element.style.marginBottom = '0'
    this.element.style.paddingTop = '0'
    this.element.style.paddingBottom = '0'
    
    // Remove from DOM after animation
    setTimeout(() => {
      this.element.remove()
    }, 300)
  }
}
