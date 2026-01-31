import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["result", "testButton", "brokerType", "name", "flexToken", "flexQueryId", "ibkrFields", "instructions"]
  static values = { url: String }

  connect() {
    this.toggleFields()
  }

  toggleFields() {
    const brokerType = this.brokerTypeTarget.value
    const isIbkr = brokerType === "ibkr"
    
    // Toggle all IBKR-specific fields
    this.ibkrFieldsTargets.forEach(el => {
      el.classList.toggle("hidden", !isIbkr)
    })
    
    // Toggle instructions box
    if (this.hasInstructionsTarget) {
      this.instructionsTarget.classList.toggle("hidden", !isIbkr)
    }
  }

  async test() {
    const button = this.testButtonTarget
    const originalText = button.textContent
    
    button.textContent = "Testing..."
    button.disabled = true

    try {
      const formData = new FormData()
      formData.append("broker_connection[broker_type]", this.brokerTypeTarget.value)
      formData.append("broker_connection[name]", this.nameTarget.value)
      
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
      result.className = "bg-emerald-50 text-emerald-700 px-4 py-3 rounded-lg border border-emerald-200 mb-4"
      
      // Handle different response formats (IBKR vs Manual)
      if (data.symbols) {
        const symbolList = data.symbols.join(", ")
        const moreText = data.count > 5 ? ` and ${data.count - 5} more` : ""
        result.textContent = `Connection successful! Found ${data.count} positions: ${symbolList}${moreText}`
      } else if (data.btc_price) {
        result.textContent = `${data.message} (BTC: $${data.btc_price.toLocaleString()})`
      } else {
        result.textContent = data.message || "Connection successful!"
      }
    } else {
      result.className = "bg-rose-50 text-rose-600 px-4 py-3 rounded-lg border border-rose-200 mb-4"
      result.textContent = `Connection failed: ${data.error}`
    }
  }
}
