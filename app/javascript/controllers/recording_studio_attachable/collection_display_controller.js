import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["carousel", "row", "card", "pill", "listOnly", "slideMedia", "preview", "previewHome"]

  static values = {
    display: String,
    activeClasses: String,
    inactiveClasses: String
  }

  connect() {
    this.onCarouselChange = () => {
      if (this.displayValue !== "carousel") return

      this.fitCarousel()
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

    this.placeCards(slides)

    if (this.hasCarouselTarget) this.carouselTarget.hidden = !slides

    this.rowTargets.forEach((row) => {
      row.hidden = slides
    })

    if (slides) {
      window.requestAnimationFrame(() => {
        this.refreshCarousel()
        window.requestAnimationFrame(() => this.fitCarousel())
      })
    }

    this.markPills()
  }

  placeCards(slides) {
    const slideNodes = this.slideNodes()
    this.separateSlides(slideNodes, slides)

    this.cardTargets.forEach((card, index) => {
      if (slides) {
        const slide = slideNodes[index]
        if (!slide) return

        slide.querySelector(".slide-placeholder")?.parentElement?.remove()
        if (card.parentElement !== slide) slide.appendChild(card)

        const filePath = card.dataset.lightboxSrc
        if (filePath) {
          slide.dataset.lightboxEnabled = "true"
          slide.dataset.lightboxSrc = filePath
          slide.dataset.lightboxAlt = card.dataset.lightboxAlt || ""
        }
      } else {
        const row = this.rowTargets[index]
        if (row && card.parentElement !== row) row.appendChild(card)
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
      if (!media || !home) return

      const destination = slides ? media : home
      if (preview.parentElement !== destination) destination.appendChild(preview)
      media.hidden = !slides
      home.hidden = slides
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

    viewport.style.height = `${height}px`
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
