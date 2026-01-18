import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.scrollLeft = this.element.scrollWidth
  }
}
