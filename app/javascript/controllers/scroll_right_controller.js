import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { target: String }

  connect() {
    // Wait for next frame to ensure DOM is fully rendered
    requestAnimationFrame(() => {
      this.scrollToTarget()
    })
  }

  scrollToTarget() {
    if (this.hasTargetValue && this.targetValue) {
      const targetEl = this.element.querySelector(this.targetValue)
      if (targetEl) {
        // Get positions relative to the scrollable container
        const containerRect = this.element.getBoundingClientRect()
        const targetRect = targetEl.getBoundingClientRect()
        
        // Calculate the target's position relative to the container's scroll
        const targetLeftRelative = targetRect.left - containerRect.left + this.element.scrollLeft
        
        // Scroll so the target is roughly centered horizontally
        const containerWidth = this.element.clientWidth
        const targetWidth = targetRect.width
        this.element.scrollLeft = targetLeftRelative - (containerWidth / 2) + (targetWidth / 2)
        return
      }
    }
    // Default: scroll to the right
    this.element.scrollLeft = this.element.scrollWidth
  }
}
