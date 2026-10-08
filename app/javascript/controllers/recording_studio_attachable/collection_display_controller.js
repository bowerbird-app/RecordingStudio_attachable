import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["carousel", "list", "pill", "slideForm", "card", "slideMedia", "preview", "previewHome"]

  static values = {
    display: String,
    activeClasses: String,
    inactiveClasses: String
  }

  connect() {
    this.keepFieldKeys = (event) => {
      const tag = (event.target?.tagName || "").toUpperCase()
      if (tag !== "INPUT" && tag !== "TEXTAREA" && tag !== "SELECT") return

      event.stopPropagation()
    }
    this.onCarouselChange = () => {
      if (this.displayValue !== "carousel") return

      this.fitCarousel()
    }
    this.cardTargets.forEach((card) => card.addEventListener("keydown", this.keepFieldKeys))
    this.element.addEventListener("carousel:change", this.onCarouselChange)
    this.apply()
  }

  disconnect() {
    this.cardTargets.forEach((card) => card.removeEventListener("keydown", this.keepFieldKeys))
    this.element.removeEventListener("carousel:change", this.onCarouselChange)
  }

  select(event) {
    event.preventDefault()
    const display = event.currentTarget.dataset.display
    if (display !== "list" && display !== "carousel") return

    this.displayValue = display
    this.apply()
  }

  async saveSlide(event) {
    event.preventDefault()
    const form = event.currentTarget
    if (form.dataset.saving === "true") return

    form.dataset.saving = "true"
    const button = form.querySelector("[data-flat-pack--unsaved-changes-target='submit']")
    if (button) button.disabled = true
    this.clearStatus(form)

    try {
      const saved = await this.postSlide(form)
      if (!saved.ok) {
        this.showStatus(form, saved.error || "Could not save.", true)
        return
      }

      this.copySavedRow(form)
      this.markSaved(form)
      this.showStatus(form, "Saved", false)
    } catch (_error) {
      this.showStatus(form, "Could not save.", true)
    } finally {
      delete form.dataset.saving
      if (button) button.disabled = false
    }
  }

  apply() {
    const slides = this.displayValue === "carousel"
    this.element.dataset.display = this.displayValue
    this.placeSlideForms(slides)

    if (this.hasCarouselTarget) this.carouselTarget.hidden = !slides
    if (this.hasListTarget) this.listTarget.hidden = slides

    if (slides) {
      window.requestAnimationFrame(() => {
        this.refreshCarousel()
        window.requestAnimationFrame(() => this.fitCarousel())
      })
    }

    this.markPills()
  }

  placeSlideForms(slides) {
    const slideNodes = this.slideNodes()
    this.separateSlides(slideNodes, slides)

    this.slideFormTargets.forEach((form, index) => {
      const slide = slideNodes[index]
      if (!slide) return

      slide.querySelector(".slide-placeholder")?.parentElement?.remove()
      if (form.parentElement !== slide) slide.appendChild(form)

      const card = form.querySelector("[data-recording-studio-attachable--collection-display-target='card']")
      const filePath = card?.dataset.lightboxSrc
      if (filePath) {
        slide.dataset.lightboxEnabled = "true"
        slide.dataset.lightboxSrc = filePath
        slide.dataset.lightboxAlt = card.dataset.lightboxAlt || ""
      }
    })

    this.placePreviews(slides)
  }

  separateSlides(slideNodes, slides) {
    slideNodes.forEach((slide, index) => {
      const showGap = slides && index < slideNodes.length - 1
      slide.style.boxSizing = "border-box"
      slide.style.paddingRight = showGap ? "1rem" : ""
    })
  }

  placePreviews(slides) {
    if (!this.hasSlideMediaTarget) return

    const mediaNodes = this.slideMediaTargets
    const previews = this.previewTargets
    const homes = this.previewHomeTargets

    previews.forEach((preview, index) => {
      const media = mediaNodes[index]
      const home = homes[index]
      if (!media) return

      if (home) {
        const destination = slides ? media : home
        if (preview.parentElement !== destination) destination.appendChild(preview)
        home.hidden = slides
      }

      media.hidden = home ? !slides : false
    })
  }

  slideNodes() {
    if (!this.hasCarouselTarget) return []

    return [...this.carouselTarget.querySelectorAll("[data-flat-pack--carousel-target='slide']")]
  }

  fitCarousel() {
    const viewport = this.carouselTarget?.querySelector("[data-flat-pack--carousel-target='viewport']")
    const slideNodes = this.slideNodes()
    if (!viewport || slideNodes.length === 0) return

    viewport.style.aspectRatio = "auto"
    viewport.style.height = "auto"
    slideNodes.forEach((slide) => {
      slide.style.height = "auto"
    })
    this.cardTargets.forEach((card) => {
      card.style.height = "auto"
    })

    const visible = slideNodes.filter((slide) => slide.getAttribute("aria-hidden") !== "true")
    const measured = (visible.length > 0 ? visible : slideNodes.slice(0, 1)).map((slide) => {
      const card = slide.querySelector("[data-recording-studio-attachable--collection-display-target='card']")
      return card?.offsetHeight || 0
    })
    const height = Math.max(0, ...measured)
    if (!height) return

    const indicatorRoom = 48
    viewport.style.height = `${height + indicatorRoom}px`
    slideNodes.forEach((slide) => {
      slide.style.height = `${height}px`
    })
  }

  refreshCarousel() {
    const carousel = this.carouselTarget?.querySelector("[data-controller~='flat-pack--carousel']")
    if (!carousel?.flatPackCarousel) return

    carousel.flatPackCarousel.refresh()
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

  async postSlide(form) {
    const body = new FormData(form)
    body.append("stay", "slide")
    const response = await fetch(form.action, {
      method: "POST",
      body,
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    const payload = await response.json().catch(() => ({}))
    return { ok: response.ok, error: payload.error }
  }

  copySavedRow(form) {
    if (!this.hasListTarget) return

    const recordingId = this.recordingId(form)
    const row = this.listRow(recordingId)
    if (!row) return

    this.copyFields(form, row)
    const listForm = this.application.getControllerForElementAndIdentifier(this.listTarget, "flat-pack--unsaved-changes")
    if (listForm && listForm.userEdited === false) this.markSaved(this.listTarget)
  }

  copyFields(form, row) {
    const fields = [...form.querySelectorAll("input, textarea")]
    fields.forEach((field) => {
      if (!this.editableField(field)) return

      const match = [...row.querySelectorAll("input, textarea")].find((item) => item.name === field.name)
      if (!match || match === field) return

      match.value = field.value
    })
  }

  editableField(field) {
    if (!field.name) return false
    if (field.name.endsWith("[recording_id]") || field.name.endsWith("[signed_editor]")) return false

    return field.name !== "redirect_mode" && field.name !== "return_to" && field.name !== "authenticity_token" && field.name !== "utf8" && field.name !== "_method"
  }

  recordingId(form) {
    const input = [...form.querySelectorAll("input")].find((item) => item.name.endsWith("[recording_id]"))
    return input ? input.value : null
  }

  listRow(recordingId) {
    if (!recordingId) return null

    return [...this.listTarget.querySelectorAll("li")].find((row) => this.recordingId(row) === recordingId) || null
  }

  markSaved(form) {
    const changes = this.application.getControllerForElementAndIdentifier(form, "flat-pack--unsaved-changes")
    if (!changes || typeof changes.captureBaseline !== "function") return

    changes.userEdited = false
    changes.captureBaseline()
  }

  showStatus(form, message, sticky) {
    const status = form.querySelector("[data-save-status]")
    if (!status) return

    this.clearStatus(form)
    status.textContent = message
    status.hidden = false
    if (sticky) return

    if (!this.statusTimers) this.statusTimers = new WeakMap()
    this.statusTimers.set(form, window.setTimeout(() => {
      status.hidden = true
      status.textContent = ""
    }, 2000))
  }

  clearStatus(form) {
    const status = form.querySelector("[data-save-status]")
    if (this.statusTimers) window.clearTimeout(this.statusTimers.get(form))
    if (!status) return

    status.hidden = true
    status.textContent = ""
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
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
