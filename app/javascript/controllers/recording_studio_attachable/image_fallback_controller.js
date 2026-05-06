import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image", "fallback"]

  showFallback() {
    if (this.hasImageTarget) {
      this.imageTarget.classList.add("hidden")
    }

    if (this.hasFallbackTarget) {
      this.fallbackTarget.classList.remove("hidden")
      this.fallbackTarget.classList.add("flex")
    }
  }
}