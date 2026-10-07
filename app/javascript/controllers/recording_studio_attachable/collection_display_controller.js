import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["carousel", "carouselHome", "row", "pill", "listOnly", "slideMedia"]

  static values = {
    display: String,
    activeClasses: String,
    inactiveClasses: String
  }

  connect() {
    this.index = 0
    this.onCarouselChange = (event) => {
      const index = event.detail?.index
      if (!Number.isInteger(index) || this.syncing || this.displayValue !== "carousel") return

      this.index = index
      this.showRow(index)
      if (this.placeCarousel()) this.syncCarouselIndex()
      else this.refreshCarousel()
    }
    this.element.addEventListener("carousel:change", this.onCarouselChange)
    this.apply()
  }

  disconnect() {
    this.element.removeEventListener("carousel:change", this.onCarouselChange)
  }

  select(event) {
    event.preventDefault()
    const display = event.currentTarget.dataset.display
    if (display !== "list" && display !== "carousel") return

    this.displayValue = display
    this.apply()
  }

  apply() {
    const slides = this.displayValue === "carousel"
    this.element.dataset.display = this.displayValue

    this.listOnlyTargets.forEach((element) => {
      element.hidden = slides
    })

    if (slides) {
      this.showRow(this.index)
    } else {
      this.rowTargets.forEach((row) => {
        row.hidden = false
      })
    }

    const moved = this.placeCarousel()
    if (slides && moved) this.syncCarouselIndex()
    else if (slides) this.refreshCarousel()
    this.markPills()
  }

  placeCarousel() {
    if (!this.hasCarouselTarget) return false

    const slides = this.displayValue === "carousel"
    this.carouselTarget.hidden = !slides
    let moved = false

    if (slides) {
      const slot = this.slideMediaTargets[this.index]
      if (slot && this.carouselTarget.parentElement !== slot) {
        slot.appendChild(this.carouselTarget)
        moved = true
      }
    } else if (this.hasCarouselHomeTarget && this.carouselTarget.parentElement !== this.carouselHomeTarget) {
      this.carouselHomeTarget.appendChild(this.carouselTarget)
      moved = true
    }

    this.slideMediaTargets.forEach((slot, index) => {
      slot.hidden = !slides || index !== this.index
    })

    return moved
  }

  syncCarouselIndex() {
    window.requestAnimationFrame(() => {
      const carousel = this.carouselTarget?.querySelector("[data-controller~='flat-pack--carousel']")
      if (!carousel?.flatPackCarousel) return

      this.syncing = true
      carousel.flatPackCarousel.to(this.index)
      this.syncing = false
    })
  }

  showRow(index) {
    this.rowTargets.forEach((row, rowIndex) => {
      row.hidden = rowIndex !== index
    })
  }

  refreshCarousel() {
    const carousel = this.carouselTarget.querySelector("[data-controller~='flat-pack--carousel']")
    if (!carousel?.flatPackCarousel) return

    window.requestAnimationFrame(() => carousel.flatPackCarousel.refresh())
  }

  markPills() {
    if (!this.hasPillTarget) return

    this.pillTargets.forEach((pill) => {
      const selected = pill.dataset.display === this.displayValue
      this.toggleClasses(pill, this.activeClassesValue, selected)
      this.toggleClasses(pill, this.inactiveClassesValue, !selected)

      if (selected) {
        pill.setAttribute("aria-current", "page")
      } else {
        pill.removeAttribute("aria-current")
      }
    })
  }

  toggleClasses(element, classList, force) {
    if (!classList) return

    classList
      .split(" ")
      .filter(Boolean)
      .forEach((className) => {
        element.classList.toggle(className, force)
      })
  }
}
