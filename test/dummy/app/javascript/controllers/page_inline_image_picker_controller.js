import { DirectUpload } from "@rails/activestorage"
import { Controller } from "@hotwired/stimulus"
import { application } from "controllers/application"

export default class extends Controller {
  static targets = ["editorHost", "searchInput", "fileInput", "status", "gallery", "emptyState", "previousButton", "nextButton", "paginationLabel"]

  static values = {
    pickerUrl: String,
    uploadUrl: String,
    directUploadUrl: String,
    modalId: String
  }

  openPickerFromToolbar(event) {
    event.preventDefault()

    const modalController = this.modalController()
    modalController?.open?.()
  }

  browseUpload() {
    this.fileInputTarget.click()
  }

  searchChanged() {}

  previousPage() {}

  nextPage() {}

  uploadSelected() {
    const [file] = this.fileInputTarget.files || []
    return if !file

    this.directUpload(file)
  }

  insertAttachment(attachment) {
    const editor = this.editorController()?.editor
    return if !editor

    const chain = editor.chain().focus()
    chain.setImage({ src: attachment.insert_url, alt: attachment.alt || attachment.name }).run()
  }

  modalController() {
    return null unless this.hasModalIdValue

    const modalElement = document.getElementById(this.modalIdValue)
    return null if !modalElement

    application.getControllerForElementAndIdentifier(modalElement, "flat-pack--modal")
  }

  editorController() {
    return null unless this.hasEditorHostTarget

    const fieldWrapper = this.editorHostTarget.querySelector('[data-controller~="flat-pack--text-area"]')
    return null if !fieldWrapper

    application.getControllerForElementAndIdentifier(fieldWrapper, "flat-pack--text-area")
  }

  directUpload(file) {
    const upload = new DirectUpload(file, this.directUploadUrlValue)

    upload.create((error, blob) => {
      this.showStatus(error ? error.message : `Uploaded ${blob.filename}`)
    })
  }

  showStatus(message) {
    return unless this.hasStatusTarget

    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("hidden", !message)
  }
}
