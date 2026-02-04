import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["period", "yearlySelect", "monthlySelect", "yearSelect", "monthSelect"]

  connect() {
    this.toggleDateFields()
  }

  toggleDateFields() {
    const isYearly = this.periodTarget.value === "yearly"
    
    if (isYearly) {
      this.yearlySelectTarget.classList.remove("hidden")
      this.monthlySelectTarget.classList.add("hidden")
      // Clear the month field when switching to yearly
      if (this.hasMonthSelectTarget) {
        this.monthSelectTarget.value = ""
      }
    } else {
      this.yearlySelectTarget.classList.add("hidden")
      this.monthlySelectTarget.classList.remove("hidden")
      // Clear the year field when switching to monthly
      if (this.hasYearSelectTarget) {
        this.yearSelectTarget.value = ""
      }
    }
  }
}
