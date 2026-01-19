import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["result", "testButton", "brokerType", "name", "accountId", "flexToken", "flexQueryId"]
  static values = { url: String }

  async test() {
    const button = this.testButtonTarget
    const originalText = button.textContent
    
    button.textContent = "Testing..."
    button.disabled = true

    try {
      const formData = new FormData()
      formData.append("broker_connection[broker_type]", this.brokerTypeTarget.value)
      formData.append("broker_connection[name]", this.nameTarget.value)
      formData.append("broker_connection[account_id]", this.accountIdTarget.value)
      
      if (this.hasFlexTokenTarget) {
        formData.append("broker_connection[flex_token]", this.flexTokenTarget.value)
      }
      if (this.hasFlexQueryIdTarget) {
        formData.append("broker_connection[flex_query_id]", this.flexQueryIdTarget.value)
      }

      const response = await fetch(this.urlValue, {
        method: "POST",
        body: formData,
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json"
        }
      })

      const data = await response.json()
      this.showResult(data)
    } catch (error) {
      this.showResult({ success: false, error: error.message })
    } finally {
      button.textContent = originalText
      button.disabled = false
    }
  }

  showResult(data) {
    const result = this.resultTarget
    result.classList.remove("hidden")

    if (data.success) {
      const symbolList = data.symbols.join(", ")
      const moreText = data.count > 5 ? ` and ${data.count - 5} more` : ""
      result.className = "bg-emerald-50 text-emerald-700 px-4 py-3 rounded-lg border border-emerald-200 mb-4"
      result.textContent = `Connection successful! Found ${data.count} positions: ${symbolList}${moreText}`
    } else {
      result.className = "bg-rose-50 text-rose-600 px-4 py-3 rounded-lg border border-rose-200 mb-4"
      result.textContent = `Connection failed: ${data.error}`
    }
  }
}
