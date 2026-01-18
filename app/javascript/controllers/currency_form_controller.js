import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  unformatAll() {
    this.inputTargets.forEach(input => {
      const value = input.value
      if (value) {
        input.value = value.replace(/[-']/g, "")
      }
    })
  }
}
