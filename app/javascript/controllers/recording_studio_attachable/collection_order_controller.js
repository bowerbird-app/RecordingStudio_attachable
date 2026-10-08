import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "order"]

  grab(event) {
    if (event.button !== 0) return

    this.draggedRow = event.currentTarget.closest("li")
    event.preventDefault()
    event.currentTarget.setPointerCapture(event.pointerId)
  }

  move(event) {
    if (!this.draggedRow || !event.currentTarget.hasPointerCapture(event.pointerId)) return

    const row = this.rowUnder(event)
    if (!row || row === this.draggedRow) return

    const box = row.getBoundingClientRect()
    const before = event.clientY < box.top + (box.height / 2)
    row.parentElement.insertBefore(this.draggedRow, before ? row : row.nextElementSibling)
    this.renumber()
  }

  release() {
    this.draggedRow = null
    this.renumber()
  }

  renumber() {
    this.orderTargets.forEach((input, index) => {
      const next = String(index + 1)
      if (input.value === next) return

      input.value = next
      input.dispatchEvent(new Event("input", { bubbles: true }))
    })
  }

  rowUnder(event) {
    const hit = document.elementFromPoint(event.clientX, event.clientY)
    const row = hit && hit.closest("li")
    if (!row || !this.element.contains(row)) return null

    return row
  }
}
