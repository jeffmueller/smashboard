import { Controller } from "@hotwired/stimulus"

// Drag-and-drop ordering using native HTML5 drag events, so there is no
// third-party sortable library to pin. Generic over what is being ordered:
// the item carries `data-reorder-id`, and the parameter name the server expects
// comes from `data-reorder-param-value`.
export default class extends Controller {
  static targets = ["item"]
  static values = { url: String, param: String }

  dragStart(event) {
    this.dragged = event.currentTarget.closest("[data-reorder-target='item']")
    if (!this.dragged) return

    this.dragged.classList.add("opacity-40")
    event.dataTransfer.effectAllowed = "move"
    // Firefox refuses to start a drag unless some data is set.
    event.dataTransfer.setData("text/plain", this.dragged.dataset.reorderId)
  }

  dragOver(event) {
    event.preventDefault()
    if (!this.dragged) return

    const over = event.currentTarget.closest("[data-reorder-target='item']")
    if (!over || over === this.dragged) return

    const items = [...this.itemTargets]

    if (items.indexOf(this.dragged) < items.indexOf(over)) {
      over.after(this.dragged)
    } else {
      over.before(this.dragged)
    }
  }

  drop(event) {
    event.preventDefault()
  }

  dragEnd() {
    if (!this.dragged) return

    this.dragged.classList.remove("opacity-40")
    this.dragged = null
    this.persist()
  }

  persist() {
    const ids = this.itemTargets.map((item) => item.dataset.reorderId)

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content,
      },
      body: JSON.stringify({ [this.paramValue]: ids }),
    })
  }
}
