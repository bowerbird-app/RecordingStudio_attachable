import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image", "fallback", "skeleton"]

  connect() {
    if (!this.hasImageTarget || this.imageTarget.complete === false) return

    if (this.imageTarget.naturalWidth > 0) {
      this.showImage()
    } else {
      this.showFallback()
    }
  }

  showImage() {
    if (this.hasSkeletonTarget) {
      this.skeletonTarget.classList.add("hidden")
    }

    if (this.hasFallbackTarget) {
      this.fallbackTarget.classList.add("hidden")
      this.fallbackTarget.classList.remove("flex")
    }

    if (this.hasImageTarget) {
      this.imageTarget.classList.remove("opacity-0")
      this.imageTarget.classList.add("opacity-100")
    }
  }

  showFallback() {
    if (this.hasSkeletonTarget) {
      this.skeletonTarget.classList.add("hidden")
    }

    if (this.hasImageTarget) {
      this.imageTarget.classList.add("hidden")
    }

    if (this.hasFallbackTarget) {
      this.fallbackTarget.classList.remove("hidden")
      this.fallbackTarget.classList.add("flex")
    }
  }
}