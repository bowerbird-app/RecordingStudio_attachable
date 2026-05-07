import { Controller } from "@hotwired/stimulus"
import { application } from "controllers/application"

export default class extends Controller {
  static targets = ["output"]

  static values = {
    modalId: String
  }

  openFromToolbar(event) {
    event.preventDefault()

    const editor = event.detail?.editor
    if (!editor || !this.hasOutputTarget) return

    this.outputTarget.value = editor.getHTML()
    this.modalController()?.open?.()
  }

  modalController() {
    if (!this.hasModalIdValue) return null

    const modalElement = document.getElementById(this.modalIdValue)
    if (!modalElement) return null

    return application.getControllerForElementAndIdentifier(modalElement, "flat-pack--modal")
  }
}