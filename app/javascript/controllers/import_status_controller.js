import { Controller } from "@hotwired/stimulus"

// Watches for status completion and triggers page reload
// When Turbo Stream replaces the content with data-status-complete="true",
// this controller will reload the page to show the full results
export default class extends Controller {
  connect() {
    this.checkComplete()
    
    // Set up a MutationObserver to watch for changes
    this.observer = new MutationObserver(() => this.checkComplete())
    this.observer.observe(this.element, { 
      childList: true, 
      subtree: true, 
      attributes: true,
      attributeFilter: ['data-status-complete']
    })
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  checkComplete() {
    if (this.element.dataset.statusComplete === "true" || 
        this.element.querySelector('[data-status-complete="true"]')) {
      // Small delay to ensure the stream has finished
      setTimeout(() => {
        Turbo.visit(window.location.href, { action: "replace" })
      }, 100)
    }
  }
}
