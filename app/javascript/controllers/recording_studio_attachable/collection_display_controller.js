import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "pager", "counter", "previous", "next", "pill", "listOnly"]

  static values = {
    display: String,
    activeClasses: String,
    inactiveClasses: String
  }

  connect() {
    this.index = 0
    this.apply()
  }

  select(event) {
    event.preventDefault()
    const display = event.currentTarget.dataset.display
    if (display !== "list" && display !== "carousel") return

    this.displayValue = display
    this.apply()
  }

  previous(event) {
    event.preventDefault()
    this.move(-1)
  }

  next(event) {
    event.preventDefault()
    this.move(1)
  }

  move(step) {
    const nextIndex = this.index + step
    if (nextIndex < 0 || nextIndex >= this.rowTargets.length) return

    this.index = nextIndex
    this.apply()
  }

  apply() {
    const slides = this.displayValue === "carousel"
    this.element.dataset.display = this.displayValue

    this.rowTargets.forEach((row, index) => {
      row.hidden = slides && index !== this.index
    })

    this.listOnlyTargets.forEach((element) => {
      element.hidden = slides
    })

    if (this.hasPagerTarget) {
      this.pagerTarget.hidden = !slides
    }

    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${this.index + 1} of ${this.rowTargets.length}`
    }

    if (this.hasPreviousTarget) this.previousTarget.disabled = this.index === 0
    if (this.hasNextTarget) this.nextTarget.disabled = this.index >= this.rowTargets.length - 1

    this.markPills()
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
