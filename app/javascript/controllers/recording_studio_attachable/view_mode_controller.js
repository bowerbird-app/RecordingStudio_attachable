import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pill", "viewInput"]

  static values = {
    activeClasses: String,
    inactiveClasses: String
  }

  connect() {
    this.syncFromLocation()
  }

  select(event) {
    const viewMode = event.currentTarget.dataset.viewMode
    if (!this.validViewMode(viewMode)) return

    this.applyViewMode(viewMode)
  }

  syncFromLocation(event) {
    if (event?.target?.id && event.target.id !== "recording-attachments-results") return

    this.applyViewMode(this.currentViewMode())
  }

  applyViewMode(viewMode) {
    if (!this.validViewMode(viewMode)) return

    if (this.hasViewInputTarget) {
      this.viewInputTarget.value = viewMode
    }

    if (!this.hasPillTarget) return

    this.pillTargets.forEach((pill) => {
      const isActive = pill.dataset.viewMode === viewMode

      this.toggleClasses(pill, this.activeClassesValue, isActive)
      this.toggleClasses(pill, this.inactiveClassesValue, !isActive)

      if (isActive) {
        pill.setAttribute("aria-current", "page")
      } else {
        pill.removeAttribute("aria-current")
      }
    })
  }

  currentViewMode() {
    const searchParams = new URLSearchParams(window.location.search)
    const requestedView = searchParams.get("view")

    if (this.validViewMode(requestedView)) return requestedView
    if (this.hasViewInputTarget && this.validViewMode(this.viewInputTarget.value)) return this.viewInputTarget.value

    return "grid"
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

  validViewMode(viewMode) {
    return viewMode === "grid" || viewMode === "list"
  }
}