import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    delay: { type: Number, default: 250 }
  }

  disconnect() {
    this.clearTimer()
  }

  queueSubmit(event) {
    if (event.target instanceof HTMLInputElement === false) return
    if (event.target.type === "hidden") return

    this.clearTimer()
    this.timeoutId = window.setTimeout(() => {
      this.element.requestSubmit()
    }, this.delayValue)
  }

  clearTimer() {
    if (!this.timeoutId) return

    window.clearTimeout(this.timeoutId)
    this.timeoutId = null
  }
}