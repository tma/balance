import { Controller } from "@hotwired/stimulus"

// Provides styled hover tooltips for SVG chart elements.
// Attach to a container wrapping an SVG chart. Any descendant SVG element
// with a `data-tooltip` attribute will show a positioned tooltip on hover.
//
// The tooltip is anchored to the hovered element (centered above it).
// By default it flips below when there's no room above. Set the
// `alwaysAbove` value to keep it above (clamped to y=0).
//
// Bar group highlighting: elements sharing a `data-bar-group` attribute
// will all be highlighted when any one of them is hovered. This is used
// for the invisible "total" rects above stacked bars.
//
// Usage:
//   <div data-controller="chart-tooltip" style="position: relative;">
//   <!-- or for bar charts that should never flip below: -->
//   <div data-controller="chart-tooltip"
//        data-chart-tooltip-always-above-value="true"
//        style="position: relative;">
//     <svg>
//       <rect data-tooltip="Label: $1,234 (56%)" data-bar-group="0" ... />
//       <rect data-tooltip="Total: $2,000" data-bar-group="0" ... />
//     </svg>
//     <div data-chart-tooltip-target="tip"></div>
//   </div>

export default class extends Controller {
  static targets = ["tip"]
  static values = { alwaysAbove: { type: Boolean, default: false } }

  connect() {
    this.handleEnter = this.handleEnter.bind(this)
    this.handleLeave = this.handleLeave.bind(this)
    this.handleTouchStart = this.handleTouchStart.bind(this)

    this.element.addEventListener("mouseenter", this.handleEnter, true)
    this.element.addEventListener("mouseleave", this.handleLeave, true)
    this.element.addEventListener("touchstart", this.handleTouchStart, { passive: true })

    this.highlightedEls = []
    this.showDelay = null
    this.hideDelay = null
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.handleEnter, true)
    this.element.removeEventListener("mouseleave", this.handleLeave, true)
    this.element.removeEventListener("touchstart", this.handleTouchStart)
    clearTimeout(this.showDelay)
    clearTimeout(this.hideDelay)
    this.hide()
  }

  handleEnter(event) {
    const el = event.target.closest("[data-tooltip]")
    if (!el) return

    // Cancel any pending hide — we're entering a new element
    clearTimeout(this.hideDelay)

    // If already showing for a different element, switch immediately
    if (this.activeElement && this.activeElement !== el) {
      this.show(el)
      return
    }

    // Small delay before showing to avoid flicker on fast sweeps
    clearTimeout(this.showDelay)
    this.showDelay = setTimeout(() => this.show(el), 30)
  }

  handleLeave(event) {
    const related = event.relatedTarget
    // Still inside a tooltip element — ignore
    if (related && related.closest?.("[data-tooltip]") === this.activeElement) return

    // Small delay before hiding so crossing between adjacent bars doesn't flash
    clearTimeout(this.showDelay)
    this.hideDelay = setTimeout(() => this.hide(), 50)
  }

  handleTouchStart(event) {
    const el = event.target.closest("[data-tooltip]")
    if (!el) {
      this.hide()
      return
    }

    // Toggle: tap same element hides, tap different shows
    if (this.activeElement === el) {
      this.hide()
      return
    }

    this.hide()
    this.show(el)
  }

  show(el) {
    this.activeElement = el

    const tip = this.tipTarget
    tip.textContent = el.dataset.tooltip
    tip.style.opacity = "1"
    tip.style.visibility = "visible"
    tip.style.transform = "translateY(0)"

    this.positionTip(tip, el)
    this.highlightBarGroup(el)
  }

  // Position the tooltip centered above the target SVG element,
  // clamped so it stays within the controller container.
  // When alwaysAbove is false (default), flips below if no room above.
  positionTip(tip, el) {
    const containerRect = this.element.getBoundingClientRect()
    const elRect = el.getBoundingClientRect()
    const tipRect = tip.getBoundingClientRect()

    // Center horizontally over the element
    const elCenterX = elRect.left + elRect.width / 2 - containerRect.left
    let x = elCenterX - tipRect.width / 2

    // Place above the element
    let y = elRect.top - containerRect.top - tipRect.height - 6

    // Clamp horizontal: keep within container
    if (x < 4) x = 4
    if (x + tipRect.width > containerRect.width - 4) {
      x = containerRect.width - tipRect.width - 4
    }

    // Vertical overflow handling
    if (y < 0) {
      if (this.alwaysAboveValue) {
        // Bar charts: clamp to top
        y = 0
      } else {
        // Donuts: flip below the element
        y = elRect.bottom - containerRect.top + 6
      }
    }

    tip.style.left = `${x}px`
    tip.style.top = `${y}px`
  }

  // When hovering an element with data-bar-group, highlight all elements
  // in the same bar group (used for total rects to highlight all segments).
  highlightBarGroup(el) {
    this.clearHighlights()

    const group = el.dataset.barGroup
    if (!group) return

    const siblings = this.element.querySelectorAll(`[data-bar-group="${group}"][data-tooltip]`)
    siblings.forEach((sibling) => {
      if (sibling !== el && sibling.getAttribute("fill") !== "transparent") {
        sibling.style.filter = "brightness(1.2)"
        this.highlightedEls.push(sibling)
      }
    })
  }

  clearHighlights() {
    this.highlightedEls.forEach((el) => {
      el.style.filter = ""
    })
    this.highlightedEls = []
  }

  hide() {
    this.activeElement = null
    this.clearHighlights()

    if (this.hasTipTarget) {
      this.tipTarget.style.opacity = "0"
      this.tipTarget.style.transform = "translateY(4px)"
      this.tipTarget.style.visibility = "hidden"
    }
  }
}
