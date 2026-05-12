import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"
import { preprocessImageFile } from "controllers/recording_studio_attachable/image_preprocessing"

export default class extends Controller {
  static targets = ["fileInput", "signedBlobInput", "submitButton", "status"]

  static values = {
    directUploadUrl: String,
    maxFileSize: Number,
    imageProcessingEnabled: Boolean,
    imageProcessingMaxWidth: Number,
    imageProcessingMaxHeight: Number,
    imageProcessingQuality: Number
  }

  connect() {
    this.uploadInFlight = false
    this.pendingSubmit = false
  }

  async fileSelected() {
    const [file] = this.fileInputTarget.files || []
    this.signedBlobInputTarget.value = ""
    if (!file) {
      this.showStatus("")
      return
    }

    this.uploadInFlight = true
    this.pendingSubmit = false
    this.toggleSubmitButton(true)

    try {
      const processed = await preprocessImageFile(file, this.imageProcessingOptions())
      const uploadFile = processed.file
      this.showStatus(processed.transformed ? `Optimizing complete. Uploading ${uploadFile.name}…` : `Uploading ${uploadFile.name}…`)

      const blob = await this.directUpload(uploadFile)
      this.signedBlobInputTarget.value = blob.signed_id
      this.showStatus(`${uploadFile.name} is ready to save.`)
    } catch (error) {
      this.signedBlobInputTarget.value = ""
      this.showStatus(error?.message || "Upload failed")
    } finally {
      this.uploadInFlight = false
      this.toggleSubmitButton(false)
      if (this.pendingSubmit) {
        this.pendingSubmit = false
        this.element.requestSubmit()
      }
    }
  }

  handleSubmit(event) {
    if (!this.uploadInFlight) return

    event.preventDefault()
    this.pendingSubmit = true
    this.showStatus("Waiting for the replacement upload to finish…")
  }

  directUpload(file) {
    return new Promise((resolve, reject) => {
      const upload = new DirectUpload(file, this.directUploadUrlValue)
      upload.create((error, blob) => {
        if (error) {
          reject(error)
          return
        }

        resolve(blob)
      })
    })
  }

  imageProcessingOptions() {
    return {
      enabled: this.imageProcessingEnabledValue,
      maxWidth: this.imageProcessingMaxWidthValue,
      maxHeight: this.imageProcessingMaxHeightValue,
      maxBytes: this.maxFileSizeValue,
      quality: this.imageProcessingQualityValue
    }
  }

  toggleSubmitButton(disabled) {
    if (!this.hasSubmitButtonTarget) return

    this.submitButtonTarget.disabled = disabled
  }

  showStatus(message) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("hidden", !message)
  }
}