import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  openPopup(event) {
    event.preventDefault()

    const url = event.currentTarget.getAttribute("href")
    if (!url) return

    const width = 640
    const height = 760
    const left = Math.max(window.screenX + (window.outerWidth - width) / 2, 0)
    const top = Math.max(window.screenY + (window.outerHeight - height) / 2, 0)
    const features = [
      "popup=yes",
      `width=${width}`,
      `height=${height}`,
      `left=${Math.round(left)}`,
      `top=${Math.round(top)}`,
      "resizable=yes",
      "scrollbars=yes"
    ].join(",")

    const popup = window.open(url, "recording-studio-attachable-provider-auth", features)
    if (popup) {
      popup.focus()
      return
    }

    window.location.href = url
  }
}