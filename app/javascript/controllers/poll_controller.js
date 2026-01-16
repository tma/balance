import { Controller } from "@hotwired/stimulus"

// Polls a URL and reloads a Turbo Frame periodically
// Stops polling when the frame contains data-poll-complete="true"
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 2000 }
  }

  connect() {
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    this.poll()
    this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, {
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "Turbo-Frame": this.element.id
        }
      })

      if (response.ok) {
        const html = await response.text()
        
        // Check if we should stop polling (status changed to completed/failed)
        if (html.includes('data-poll-complete="true"') || html.includes("data-poll-complete='true'")) {
          this.stopPolling()
          // Do a full Turbo visit to load the complete page with transactions
          Turbo.visit(window.location.href)
        } else {
          // Update the frame content
          this.element.innerHTML = html
        }
      }
    } catch (error) {
      console.error("Polling error:", error)
    }
  }
}
