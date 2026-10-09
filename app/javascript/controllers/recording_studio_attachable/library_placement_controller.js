import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "attachmentId", "uploadLibraryId", "switcher"]
  static values = { libraries: Object }

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

  switchLibrary(event) {
    const libraryId = event.target?.value
    const library = this.librariesValue?.[libraryId]
    if (!libraryId || !library) return

    if (this.hasUploadLibraryIdTarget) this.uploadLibraryIdTarget.value = libraryId

    const picker = this.application.getControllerForElementAndIdentifier(
      this.element,
      "recording-studio-attachable--attachment-image-picker"
    )
    if (!picker) return

    if (library.pickerUrl) picker.pickerUrlValue = library.pickerUrl
    if (library.uploadUrl) picker.uploadUrlValue = library.uploadUrl
  }
}
