import { Controller } from "@hotwired/stimulus"

// Opens the standard upload page inside a FlatPack modal.
// The modal body is a lazy turbo frame. Its src is set on the first open so
// nothing loads until someone asks to upload. After the uploader announces
// attachable:uploaded, this reloads a host Turbo frame when one was named,
// otherwise the current page.
export default class extends Controller {
  static targets = ["frame"]
  static values = {
    src: String,
    refreshFrame: String
  }

  load() {
    if (!this.hasFrameTarget || !this.srcValue) return
    if (this.frameTarget.getAttribute("src")) return

    this.frameTarget.setAttribute("src", this.srcValue)
  }

  uploaded(event) {
    if (event.target.closest("[data-controller~='recording-studio-attachable--upload-modal']") !== this.element) return

    event.stopPropagation()
    // finishUpload still clears the queue and closes the modal on this turn.
    // Refresh once that returns so the uploader is not removed mid-call.
    queueMicrotask(() => {
      this.resetFrame()
      this.refreshHost()
    })
  }

  resetFrame() {
    if (!this.hasFrameTarget) return

    const placeholder = this.frameTarget.dataset.placeholderHtml || ""
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = placeholder
  }

  refreshHost() {
    window.Turbo?.cache?.clear?.()

    const frame = this.hostFrame()
    if (frame) {
      this.reloadFrame(frame)
      return
    }

    if (window.Turbo?.visit) {
      window.Turbo.visit(window.location.href, { action: "replace" })
      return
    }

    window.location.reload()
  }

  hostFrame() {
    const frameId = this.refreshFrameValue
    if (!frameId) return null

    const frame = document.getElementById(frameId)
    if (!frame || frame.tagName !== "TURBO-FRAME") return null

    return frame
  }

  reloadFrame(frame) {
    const url = new URL(frame.getAttribute("src") || window.location.href, window.location.href)
    url.searchParams.set("attachable_refresh", String(Date.now()))
    frame.removeAttribute("src")
    frame.setAttribute("src", `${url.pathname}${url.search}${url.hash}`)
  }
}
