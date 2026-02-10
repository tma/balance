import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    prevUrl: String,
    nextUrl: String,
    prevYearUrl: String,
    nextYearUrl: String
  }

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(event) {
    // Don't trigger if user is typing in an input/textarea
    if (event.target.matches("input, textarea, select, [contenteditable]")) {
      return
    }

    // Don't trigger if modifier keys are pressed (except shift for year navigation)
    if (event.metaKey || event.ctrlKey || event.altKey) {
      return
    }

    if (event.shiftKey) {
      // Shift+Arrow: year navigation
      if ((event.key === "ArrowLeft" || event.key === "K") && this.hasPrevYearUrlValue) {
        event.preventDefault()
        this.navigate(this.prevYearUrlValue)
      } else if ((event.key === "ArrowRight" || event.key === "J") && this.hasNextYearUrlValue) {
        event.preventDefault()
        this.navigate(this.nextYearUrlValue)
      }
      return
    }

    if ((event.key === "ArrowLeft" || event.key === "k") && this.hasPrevUrlValue) {
      event.preventDefault()
      this.navigate(this.prevUrlValue)
    } else if ((event.key === "ArrowRight" || event.key === "j") && this.hasNextUrlValue) {
      event.preventDefault()
      this.navigate(this.nextUrlValue)
    }
  }

  navigateLink(event) {
    event.preventDefault()
    const url = event.currentTarget.href
    this.navigate(url)
  }

  navigate(url) {
    // Use fetch + morphing to update content without scroll jump
    fetch(url, {
      headers: {
        "Accept": "text/html",
        "Turbo-Frame": "_top"
      }
    })
    .then(response => response.text())
    .then(html => {
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, "text/html")
      const newContent = doc.querySelector("[data-controller='month-navigation']")
      
      if (newContent) {
        // Update URL without scrolling
        history.pushState({}, "", url)
        
        // Morph the content
        this.element.innerHTML = newContent.innerHTML
        
        // Update controller values
        const prevUrl = newContent.dataset.monthNavigationPrevUrlValue
        const nextUrl = newContent.dataset.monthNavigationNextUrlValue
        const prevYearUrl = newContent.dataset.monthNavigationPrevYearUrlValue
        const nextYearUrl = newContent.dataset.monthNavigationNextYearUrlValue
        
        if (prevUrl) {
          this.prevUrlValue = prevUrl
        } else {
          delete this.element.dataset.monthNavigationPrevUrlValue
        }
        
        if (nextUrl) {
          this.nextUrlValue = nextUrl
        } else {
          delete this.element.dataset.monthNavigationNextUrlValue
        }

        if (prevYearUrl) {
          this.prevYearUrlValue = prevYearUrl
        } else {
          delete this.element.dataset.monthNavigationPrevYearUrlValue
        }

        if (nextYearUrl) {
          this.nextYearUrlValue = nextYearUrl
        } else {
          delete this.element.dataset.monthNavigationNextYearUrlValue
        }
      }
    })
  }
}
