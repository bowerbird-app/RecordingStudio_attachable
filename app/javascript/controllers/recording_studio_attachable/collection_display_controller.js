import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["carousel", "row", "pill", "listOnly"]

  static values = {
    display: String,
    activeClasses: String,
    inactiveClasses: String
  }

  connect() {
    this.index = 0
    this.onCarouselChange = (event) => {
      const index = event.detail?.index
      if (!Number.isInteger(index)) return

      this.index = index
      if (this.displayValue === "carousel") this.showRow(index)
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

    if (this.hasCarouselTarget) this.carouselTarget.hidden = !slides

    this.listOnlyTargets.forEach((element) => {
      element.hidden = slides
    })

    if (slides) {
      this.showRow(this.index)
      this.refreshCarousel()
    } else {
      this.rowTargets.forEach((row) => {
        row.hidden = false
      })
    }

    this.markPills()
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
