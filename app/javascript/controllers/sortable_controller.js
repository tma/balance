import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]
  static values = { url: String, type: String }

  connect() {
    this.itemTargets.forEach(item => {
      // For groups, make only the header row draggable
      const dragHandle = this.typeValue === "group" 
        ? item.querySelector(".group-header") 
        : item
      
      if (dragHandle) {
        dragHandle.setAttribute("draggable", true)
        dragHandle.addEventListener("dragstart", this.dragStart.bind(this))
        dragHandle.addEventListener("dragend", this.dragEnd.bind(this))
      }
      
      item.addEventListener("dragover", this.dragOver.bind(this))
      item.addEventListener("drop", this.drop.bind(this))
    })
  }

  dragStart(event) {
    if (this.typeValue === "group") {
      // For groups, the item is the tbody, find it from the header row
      this.draggedItem = event.target.closest("[data-sortable-target='item']")
      // Also get the following assets tbody to move with it
      this.draggedAssetsTbody = this.draggedItem.nextElementSibling
    } else {
      this.draggedItem = event.target.closest("[data-sortable-target='item']")
    }
    this.draggedItem.classList.add("opacity-50")
    event.dataTransfer.effectAllowed = "move"
  }

  dragOver(event) {
    event.preventDefault()
    const item = event.target.closest("[data-sortable-target='item']")
    if (item && item !== this.draggedItem) {
      const rect = item.getBoundingClientRect()
      const midpoint = rect.top + rect.height / 2
      
      if (this.typeValue === "group") {
        // For groups, move the tbody and its following assets tbody together
        const targetAssetsTbody = item.nextElementSibling
        if (event.clientY < midpoint) {
          item.parentNode.insertBefore(this.draggedItem, item)
          item.parentNode.insertBefore(this.draggedAssetsTbody, item)
        } else {
          const insertPoint = targetAssetsTbody ? targetAssetsTbody.nextSibling : null
          item.parentNode.insertBefore(this.draggedItem, insertPoint)
          item.parentNode.insertBefore(this.draggedAssetsTbody, insertPoint)
        }
      } else {
        if (event.clientY < midpoint) {
          item.parentNode.insertBefore(this.draggedItem, item)
        } else {
          item.parentNode.insertBefore(this.draggedItem, item.nextSibling)
        }
      }
    }
  }

  drop(event) {
    event.preventDefault()
  }

  dragEnd(event) {
    this.draggedItem.classList.remove("opacity-50")
    this.saveOrder()
  }

  saveOrder() {
    const positions = {}
    this.itemTargets.forEach((item, index) => {
      positions[item.dataset.id] = index
    })

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      },
      body: JSON.stringify({ positions })
    })
  }
}
