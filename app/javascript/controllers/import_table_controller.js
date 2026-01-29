import { Controller } from "@hotwired/stimulus"

// Handles import review table interactions:
// - Click row to toggle selection
// - Arrow keys to navigate rows
// - Space to toggle selection
// - T to cycle transaction type
// - C to focus category dropdown
// - X to toggle selection (alternative to space)
export default class extends Controller {
  static targets = ["row", "selectAll", "selectedCount"]

  connect() {
    this.currentIndex = -1
    this.bindKeyboardEvents()
    this.highlightEmptyCategories()
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  bindKeyboardEvents() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(event) {
    // Don't handle if user is typing in an input or select
    if (event.target.matches("input:not([type='checkbox']), textarea")) {
      return
    }

    // Allow select dropdowns to handle their own keys
    if (event.target.matches("select")) {
      if (!["Escape", "ArrowUp", "ArrowDown"].includes(event.key) || !event.altKey) {
        return
      }
    }

    switch (event.key) {
      case "ArrowDown":
      case "j":
        event.preventDefault()
        this.moveSelection(1)
        break
      case "ArrowUp":
      case "k":
        event.preventDefault()
        this.moveSelection(-1)
        break
      case " ":
      case "x":
        if (this.currentIndex >= 0) {
          event.preventDefault()
          this.toggleCurrentRow()
        }
        break
      case "t":
        if (this.currentIndex >= 0) {
          event.preventDefault()
          this.cycleTransactionType()
        }
        break
      case "c":
        if (this.currentIndex >= 0) {
          event.preventDefault()
          this.focusCategory()
        }
        break
      case "a":
        if (event.metaKey || event.ctrlKey) {
          event.preventDefault()
          this.selectAll()
        }
        break
      case "Escape":
        this.clearSelection()
        event.target.blur?.()
        break
    }
  }

  // Click on a row to toggle its checkbox
  rowClicked(event) {
    // Don't toggle if clicking on or within interactive elements
    if (event.target.closest("input, select, button, a, label")) {
      return
    }

    const row = event.currentTarget
    const index = this.rowTargets.indexOf(row)
    
    this.setCurrentIndex(index)
    this.toggleCurrentRow()
  }

  // Move selection up or down
  moveSelection(delta) {
    const newIndex = this.currentIndex + delta
    
    if (newIndex >= 0 && newIndex < this.rowTargets.length) {
      this.setCurrentIndex(newIndex)
      this.scrollRowIntoView()
    } else if (this.currentIndex === -1 && delta > 0) {
      // Start at first row if nothing selected
      this.setCurrentIndex(0)
      this.scrollRowIntoView()
    }
  }

  setCurrentIndex(index) {
    // Remove highlight from previous row
    if (this.currentIndex >= 0 && this.rowTargets[this.currentIndex]) {
      this.rowTargets[this.currentIndex].classList.remove("ring-2", "ring-cyan-500", "ring-inset")
    }

    this.currentIndex = index

    // Add highlight to new row
    if (this.currentIndex >= 0 && this.rowTargets[this.currentIndex]) {
      this.rowTargets[this.currentIndex].classList.add("ring-2", "ring-cyan-500", "ring-inset")
    }
  }

  scrollRowIntoView() {
    const row = this.rowTargets[this.currentIndex]
    if (row) {
      row.scrollIntoView({ block: "nearest", behavior: "smooth" })
    }
  }

  toggleCurrentRow() {
    const row = this.rowTargets[this.currentIndex]
    if (!row) return

    const checkbox = row.querySelector(".transaction-checkbox")
    if (checkbox) {
      checkbox.checked = !checkbox.checked
      this.updateSelectedCount()
    }
  }

  cycleTransactionType() {
    const row = this.rowTargets[this.currentIndex]
    if (!row) return

    const select = row.querySelector("select[name*='[transaction_type]']")
    if (select) {
      // Toggle between expense and income
      select.value = select.value === "expense" ? "income" : "expense"
      // Trigger change event for any listeners
      select.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }

  focusCategory() {
    const row = this.rowTargets[this.currentIndex]
    if (!row) return

    const select = row.querySelector("select[name*='[category_id]']")
    if (select) {
      select.focus()
      // Open the dropdown - showPicker() is the modern way, fallback to simulating keys
      if (typeof select.showPicker === "function") {
        try {
          select.showPicker()
        } catch (e) {
          // showPicker can fail if not triggered by user gesture in some browsers
          this.simulateSelectOpen(select)
        }
      } else {
        this.simulateSelectOpen(select)
      }
    }
  }

  simulateSelectOpen(select) {
    // Simulate Alt+Down or Space to open dropdown (cross-browser)
    const event = new KeyboardEvent("keydown", {
      key: " ",
      code: "Space",
      bubbles: true
    })
    select.dispatchEvent(event)
  }

  selectAll() {
    const checked = !this.allSelectableSelected()
    
    this.rowTargets.forEach(row => {
      if (!row.classList.contains("duplicate-row") && !row.classList.contains("ignored-row")) {
        const checkbox = row.querySelector(".transaction-checkbox")
        if (checkbox) {
          checkbox.checked = checked
        }
      }
    })

    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = checked
    }

    this.updateSelectedCount()
  }

  allSelectableSelected() {
    return this.rowTargets
      .filter(row => !row.classList.contains("duplicate-row") && !row.classList.contains("ignored-row"))
      .every(row => {
        const checkbox = row.querySelector(".transaction-checkbox")
        return checkbox?.checked
      })
  }

  clearSelection() {
    this.setCurrentIndex(-1)
  }

  // Handle select all checkbox change
  selectAllChanged(event) {
    const checked = event.target.checked
    
    this.rowTargets.forEach(row => {
      if (!row.classList.contains("duplicate-row") && !row.classList.contains("ignored-row")) {
        const checkbox = row.querySelector(".transaction-checkbox")
        if (checkbox) {
          checkbox.checked = checked
        }
      }
    })

    this.updateSelectedCount()
  }

  // Handle individual checkbox change
  checkboxChanged() {
    this.updateSelectedCount()
    
    // Update select all checkbox state
    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = this.allSelectableSelected()
    }
  }

  updateSelectedCount() {
    if (this.hasSelectedCountTarget) {
      const count = this.rowTargets.filter(row => {
        const checkbox = row.querySelector(".transaction-checkbox")
        return checkbox?.checked
      }).length
      
      this.selectedCountTarget.textContent = count
    }
  }

  // Category highlighting for empty selections
  highlightEmptyCategories() {
    this.element.querySelectorAll('.transaction-category').forEach(select => {
      this.updateCategoryHighlight(select)
    })
  }

  updateCategoryHighlight(select) {
    // Don't highlight ignored or duplicate rows
    const row = select.closest('tr')
    if (row?.classList.contains('ignored-row') || row?.classList.contains('duplicate-row')) {
      select.classList.remove('border-amber-400', 'bg-amber-50', 'dark:bg-amber-900/30')
      select.classList.add('border-slate-300', 'dark:border-slate-600')
      return
    }

    if (!select.value) {
      select.classList.add('border-amber-400', 'bg-amber-50', 'dark:bg-amber-900/30')
      select.classList.remove('border-slate-300', 'dark:border-slate-600')
    } else {
      select.classList.remove('border-amber-400', 'bg-amber-50', 'dark:bg-amber-900/30')
      select.classList.add('border-slate-300', 'dark:border-slate-600')
    }
  }

  categoryChanged(event) {
    this.updateCategoryHighlight(event.target)
  }
}
