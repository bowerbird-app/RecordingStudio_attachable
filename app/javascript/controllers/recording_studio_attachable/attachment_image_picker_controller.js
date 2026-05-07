import { DirectUpload } from "@rails/activestorage"
import { Controller } from "@hotwired/stimulus"
import { application } from "controllers/application"

export default class extends Controller {
  static targets = ["editorHost", "searchInput", "fileInput", "status", "gallery", "emptyState", "previousButton", "nextButton", "paginationLabel"]

  static values = {
    pickerUrl: String,
    uploadUrl: String,
    directUploadUrl: String,
    modalId: String,
    searchDelay: { type: Number, default: 250 }
  }

  connect() {
    this.currentPage = 1
    this.totalPages = 1
    this.searchTimeoutId = null
    this.activeEditor = null
  }

  disconnect() {
    if (this.searchTimeoutId) {
      window.clearTimeout(this.searchTimeoutId)
      this.searchTimeoutId = null
    }
  }

  openPickerFromToolbar(event) {
    event.preventDefault()

    this.activeEditor = event.detail?.editor || this.editorController()?.editor || null
    this.currentPage = 1
    this.loadAttachments()
    this.modalController()?.open?.()
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
      this.loadAttachments()
    }, this.searchDelayValue)
  }

  previousPage() {
    if (this.currentPage <= 1) return

    this.currentPage -= 1
    this.loadAttachments()
  }

  nextPage() {
    if (this.currentPage >= this.totalPages) return

    this.currentPage += 1
    this.loadAttachments()
  }

  uploadSelected() {
    const [file] = this.fileInputTarget.files || []
    if (!file) return

    this.directUpload(file)
  }

  async loadAttachments() {
    if (!this.hasPickerUrlValue) return

    this.showStatus("Loading images…")

    try {
      const response = await fetch(this.pickerRequestUrl(), {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })

      if (!response.ok) {
        throw new Error("Unable to load image library")
      }

      const payload = await response.json()
      this.renderGallery(payload.attachments || [])
      this.updatePagination(payload.pagination || {})
      this.showStatus("")
    } catch (error) {
      this.renderGallery([])
      this.updatePagination({ current_page: 1, total_pages: 1, previous_page: false, next_page: false })
      this.showStatus(error.message || "Unable to load image library")
    }
  }

  insertAttachment(attachment) {
    const editor = this.activeEditor || this.editorController()?.editor
    if (!editor) return

    editor.chain().focus().setImage({ src: attachment.insert_url, alt: attachment.alt || attachment.name }).run()
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

  directUpload(file) {
    this.showStatus(`Uploading ${file.name}…`)

    const upload = new DirectUpload(file, this.directUploadUrlValue)

    upload.create(async (error, blob) => {
      if (error) {
        this.showStatus(error.message)
        return
      }

      try {
        const attachment = await this.createAttachmentFromBlob(file, blob)
        this.insertAttachment(attachment)
        this.showStatus(`Inserted ${attachment.name}`)
        this.currentPage = 1
        this.loadAttachments()
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

  renderGallery(attachments) {
    if (!this.hasGalleryTarget) return

    this.galleryTarget.innerHTML = ""

    attachments.forEach((attachment) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "group flex h-full flex-col overflow-hidden rounded-xl border border-(--surface-border-color) bg-(--surface-background-color) text-left shadow-sm transition hover:border-(--surface-content-color) hover:shadow-md focus:outline-none focus:ring-2 focus:ring-ring"
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

      const body = document.createElement("div")
      body.className = "space-y-1 p-3"

      const title = document.createElement("p")
      title.className = "truncate text-sm font-semibold text-(--surface-content-color)"
      title.textContent = attachment.name || "Untitled image"

      const meta = document.createElement("p")
      meta.className = "text-xs text-(--surface-muted-content-color)"
      meta.textContent = attachment.description || "Insert inline"

      body.appendChild(title)
      body.appendChild(meta)
      button.appendChild(media)
      button.appendChild(body)
      this.galleryTarget.appendChild(button)
    })

    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.toggle("hidden", attachments.length > 0)
    }
  }

  updatePagination(pagination) {
    this.currentPage = Number(pagination.current_page || 1)
    this.totalPages = Number(pagination.total_pages || 1)

    if (this.hasPaginationLabelTarget) {
      this.paginationLabelTarget.textContent = `Page ${this.currentPage} of ${this.totalPages}`
    }

    if (this.hasPreviousButtonTarget) {
      this.previousButtonTarget.disabled = !pagination.previous_page
    }

    if (this.hasNextButtonTarget) {
      this.nextButtonTarget.disabled = !pagination.next_page
    }
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
}