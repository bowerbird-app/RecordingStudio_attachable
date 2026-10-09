import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "attachmentId"]

  addFromLibrary(event) {
    const attachment = event.detail?.attachment
    if (!attachment?.id || !this.hasFormTarget || !this.hasAttachmentIdTarget) return

    this.attachmentIdTarget.value = attachment.id
    this.formTarget.requestSubmit()
  }

  browseUpload(event) {
    const button = event.currentTarget
    const form = button.closest("form")
    const input = form?.querySelector("input[type=file]")
    input?.click()
  }
}
