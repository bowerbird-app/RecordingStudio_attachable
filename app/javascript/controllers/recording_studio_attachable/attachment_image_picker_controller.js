import { DirectUpload } from "@rails/activestorage"
import { Controller } from "@hotwired/stimulus"
import { application } from "controllers/application"
import { preprocessImageFile } from "controllers/recording_studio_attachable/image_preprocessing"

export default class extends Controller {
  static targets = ["editorHost", "searchInput", "fileInput", "status", "scrollContainer", "gallery", "emptyState"]

  static values = {
    pickerUrl: String,
    uploadUrl: String,
    directUploadUrl: String,
    modalId: String,
    maxFileSize: Number,
    imageProcessingEnabled: Boolean,
    imageProcessingMaxWidth: Number,
    imageProcessingMaxHeight: Number,
    imageProcessingQuality: Number,
    searchDelay: { type: Number, default: 250 }
  }

  connect() {
    this.currentPage = 1
    this.totalPages = 1
    this.hasNextPage = false
    this.isLoading = false
    this.searchTimeoutId = null
    this.activeEditor = null
    this.boundHandleScroll = this.handleScroll.bind(this)

    if (this.hasScrollContainerTarget) {
      this.scrollContainerTarget.addEventListener("scroll", this.boundHandleScroll)
    }
  }

  disconnect() {
    if (this.searchTimeoutId) {
      window.clearTimeout(this.searchTimeoutId)
      this.searchTimeoutId = null
    }

    if (this.hasScrollContainerTarget) {
      this.scrollContainerTarget.removeEventListener("scroll", this.boundHandleScroll)
    }
  }

  openPickerFromToolbar(event) {
    event.preventDefault()

    this.activeEditor = event.detail?.editor || this.editorController()?.editor || null
    this.modalController()?.open?.()
    this.currentPage = 1
    this.loadAttachments({ reset: true })
  }

  browseUpload() {
    this.fileInputTarget.click()
  }

  searchChanged() {
    if (this.searchTimeoutId) {
      window.clearTimeout(this.searchTimeoutId)
    }

    this.searchTimeoutId = window.setTimeout(() => {
      this.currentPage = 1
      this.loadAttachments({ reset: true })
    }, this.searchDelayValue)
  }

  uploadSelected() {
    const [file] = this.fileInputTarget.files || []
    if (!file) return

    this.directUpload(file)
  }

  handleScroll() {
    if (!this.hasScrollContainerTarget || this.isLoading || !this.hasNextPage) return

    const { scrollTop, clientHeight, scrollHeight } = this.scrollContainerTarget
    if (scrollTop + clientHeight < scrollHeight - 120) return

    this.currentPage += 1
    this.loadAttachments({ append: true })
  }

  async loadAttachments({ append = false, reset = false } = {}) {
    if (!this.hasPickerUrlValue || this.isLoading) return

    if (reset) {
      this.currentPage = 1
      this.totalPages = 1
      this.hasNextPage = false

      if (this.hasScrollContainerTarget) {
        this.scrollContainerTarget.scrollTop = 0
      }
    }

    this.showStatus("")
    this.isLoading = true

    try {
      const response = await fetch(this.pickerRequestUrl(), {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })

      if (!response.ok) {
        throw new Error("Unable to load image library")
      }

      const payload = await response.json()
      this.renderGallery(payload.attachments || [], { append })
      this.updatePagination(payload.pagination || {})
      this.showStatus("")
      this.isLoading = false
      this.fillScrollContainer()
    } catch (error) {
      this.renderGallery([], { append: false })
      this.updatePagination({ current_page: 1, total_pages: 1, previous_page: false, next_page: false })
      this.showStatus(error.message || "Unable to load image library")
      this.isLoading = false
    } finally {
      this.searchTimeoutId = null
    }
  }

  insertAttachment(attachment) {
    const editor = this.activeEditor || this.editorController()?.editor
    if (!editor) return

    editor.chain().focus().setImage({
      src: attachment.insert_url,
      alt: attachment.alt || attachment.name,
      attachmentId: attachment.id,
      showPath: attachment.show_path,
      display: "medium",
      align: "center",
    }).run()
    this.modalController()?.close?.()
  }

  modalController() {
    if (!this.hasModalIdValue) return null

    const modalElement = document.getElementById(this.modalIdValue)
    if (!modalElement) return null

    return application.getControllerForElementAndIdentifier(modalElement, "flat-pack--modal")
  }

  editorController() {
    if (!this.hasEditorHostTarget) return null

    const fieldWrapper = this.editorHostTarget.querySelector('[data-controller~="flat-pack--text-area"]')
    if (!fieldWrapper) return null

    return application.getControllerForElementAndIdentifier(fieldWrapper, "flat-pack--text-area")
  }

  async directUpload(file) {
    const processed = await preprocessImageFile(file, this.imageProcessingOptions())
    const uploadFile = processed.file
    this.showStatus(processed.transformed ? `Optimizing complete. Uploading ${uploadFile.name}…` : `Uploading ${uploadFile.name}…`)

    const upload = new DirectUpload(uploadFile, this.directUploadUrlValue)

    upload.create(async (error, blob) => {
      if (error) {
        this.showStatus(error.message)
        return
      }

      try {
        const attachment = await this.createAttachmentFromBlob(uploadFile, blob)
        this.insertAttachment(attachment)
        this.showStatus(`Inserted ${attachment.name}`)
        this.currentPage = 1
        this.loadAttachments({ reset: true })
      } catch (uploadError) {
        this.showStatus(uploadError.message || "Unable to add image")
      } finally {
        this.fileInputTarget.value = ""
      }
    })
  }

  async createAttachmentFromBlob(file, blob) {
    const response = await fetch(this.uploadUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({
        attachments: [
          {
            signed_blob_id: blob.signed_id,
            name: this.defaultAttachmentName(file)
          }
        ]
      })
    })

    const payload = await response.json()
    if (!response.ok) {
      throw new Error(payload.error || "Unable to add image")
    }

    const [attachment] = payload.attachments || []
    if (!attachment) {
      throw new Error("Upload completed without an attachment payload")
    }

    return attachment
  }

  pickerRequestUrl() {
    const url = new URL(this.pickerUrlValue, window.location.origin)
    const query = this.searchQuery()

    url.searchParams.set("page", this.currentPage)
    if (query) {
      url.searchParams.set("q", query)
    } else {
      url.searchParams.delete("q")
    }

    return url.toString()
  }

  renderGallery(attachments, { append = false } = {}) {
    if (!this.hasGalleryTarget) return

    if (!append) {
      this.galleryTarget.innerHTML = ""
    }

    attachments.forEach((attachment) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "group flex h-full flex-col overflow-hidden rounded-xl border border-(--surface-border-color) bg-(--surface-background-color) text-left shadow-sm transition hover:border-(--surface-content-color) hover:shadow-md focus:outline-none focus:ring-2 focus:ring-ring"
      button.setAttribute("aria-label", attachment.name || "Untitled image")
      button.addEventListener("click", () => this.insertAttachment(attachment))

      const media = document.createElement("div")
      media.className = "relative aspect-4/3 overflow-hidden bg-(--surface-muted-background-color)"

      if (attachment.thumbnail_url) {
        const image = document.createElement("img")
        image.src = attachment.thumbnail_url
        image.alt = attachment.alt || attachment.name || "Attachment image"
        image.className = "h-full w-full object-cover transition group-hover:scale-[1.02]"
        media.appendChild(image)
      }

      button.appendChild(media)
      this.galleryTarget.appendChild(button)
    })

    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.toggle("hidden", attachments.length > 0)
    }
  }

  updatePagination(pagination) {
    this.currentPage = Number(pagination.current_page || 1)
    this.totalPages = Number(pagination.total_pages || 1)
    this.hasNextPage = Boolean(pagination.next_page)
  }

  fillScrollContainer() {
    if (!this.hasScrollContainerTarget || this.isLoading || !this.hasNextPage) return

    const { clientHeight, scrollHeight } = this.scrollContainerTarget
    if (scrollHeight > clientHeight + 8) return

    this.currentPage += 1
    this.loadAttachments({ append: true })
  }

  showStatus(message) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("hidden", !message)
  }

  defaultAttachmentName(file) {
    return file.name.replace(/\.[^.]+$/, "") || file.name
  }

  searchQuery() {
    if (!this.hasSearchInputTarget) return ""

    const field = this.searchInputTarget instanceof HTMLInputElement
      ? this.searchInputTarget
      : this.searchInputTarget.querySelector("input")

    return field?.value?.trim() || ""
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
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
}