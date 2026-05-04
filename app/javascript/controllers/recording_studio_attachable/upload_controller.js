import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = ["dropzone", "input", "queue", "emptyState", "finalizeButton"]
  static values = {
    directUploadUrl: String,
    finalizeUrl: String,
    maxFileSize: Number,
    maxFilesCount: Number,
    allowedContentTypes: String
  }

  connect() {
    this.files = []
    this.bindDropzoneEvents()
  }

  disconnect() {
    this.files.forEach((entry) => this.revokePreview(entry))
  }

  browse() {
    this.inputTarget.click()
  }

  filesSelected(event) {
    this.addFiles(Array.from(event.target.files || []))
    event.target.value = null
  }

  finalize() {
    const readyEntries = this.files.filter((entry) => entry.status === "uploaded")
    if (readyEntries.length === 0) return

    readyEntries.forEach((entry) => {
      entry.status = "finalizing"
      this.renderEntry(entry)
    })

    fetch(this.finalizeUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "",
        Accept: "application/json"
      },
      body: JSON.stringify({
        attachments: readyEntries.map((entry) => ({
          signed_blob_id: entry.signedBlobId,
          name: entry.name,
          description: entry.description
        }))
      })
    })
      .then(async (response) => {
        const payload = await response.json()
        if (!response.ok) throw payload
        readyEntries.forEach((entry) => {
          entry.status = "attached"
          this.renderEntry(entry)
        })
        window.location.href = payload.redirect_path || this.finalizeUrlValue
      })
      .catch((error) => {
        const errorsByBlobId = new Map(
          Array.from(error?.errors || []).map((item) => [item.signed_blob_id, item.error])
        )

        readyEntries.forEach((entry) => {
          entry.status = "failed"
          entry.error = errorsByBlobId.get(entry.signedBlobId) || error?.error || "Finalization failed"
          this.renderEntry(entry)
        })
      })
  }

  retry(event) {
    const id = event.currentTarget.dataset.id
    const entry = this.files.find((item) => item.id === id)
    if (!entry) return

    entry.error = null
    if (entry.signedBlobId) {
      entry.status = "uploaded"
      this.renderEntry(entry)
      this.updateFinalizeButton()
    } else {
      this.uploadEntry(entry)
    }
  }

  remove(event) {
    const id = event.currentTarget.dataset.id
    const entry = this.files.find((item) => item.id === id)
    this.files = this.files.filter((item) => item.id !== id)
    this.revokePreview(entry)
    this.renderQueue()
  }

  bindDropzoneEvents() {
    ;["dragenter", "dragover"].forEach((eventName) => {
      this.dropzoneTarget.addEventListener(eventName, (event) => {
        event.preventDefault()
        this.dropzoneTarget.classList.add("ring-2", "ring-[var(--brand-primary-color)]")
      })
    })

    ;["dragleave", "drop"].forEach((eventName) => {
      this.dropzoneTarget.addEventListener(eventName, (event) => {
        event.preventDefault()
        this.dropzoneTarget.classList.remove("ring-2", "ring-[var(--brand-primary-color)]")
      })
    })

    this.dropzoneTarget.addEventListener("drop", (event) => {
      const files = Array.from(event.dataTransfer?.files || [])
      this.addFiles(files)
    })
  }

  addFiles(files) {
    const availableSlots = this.hasMaxFilesCountValue
      ? Math.max(this.maxFilesCountValue - this.queueableEntryCount(), 0)
      : files.length

    files.forEach((file, index) => {
      const exceedsCount = this.hasMaxFilesCountValue && index >= availableSlots
      const entry = {
        id: crypto.randomUUID(),
        file,
        name: file.name.replace(/\.[^.]+$/, ""),
        description: "",
        previewUrl: file.type.startsWith("image/") ? URL.createObjectURL(file) : null,
        progress: 0,
        status: exceedsCount ? "invalid" : this.validateFile(file),
        error: null,
        signedBlobId: null
      }
      if (exceedsCount) {
        entry.error = this.maxFilesError()
      } else if (entry.status === "invalid") {
        entry.error = this.validationError(file)
      }
      this.files.push(entry)
      this.renderQueue()
      if (entry.status === "pending") this.uploadEntry(entry)
    })
  }

  uploadEntry(entry) {
    entry.status = "uploading"
    this.renderEntry(entry)

    const upload = new DirectUpload(entry.file, this.directUploadUrlValue, {
      directUploadWillStoreFileWithXHR: (request) => this.bindUploadProgress(request, entry)
    })

    upload.create((error, blob) => {
      if (error) {
        entry.status = "failed"
        entry.error = error?.message || String(error)
      } else {
        entry.status = "uploaded"
        entry.progress = 100
        entry.signedBlobId = blob.signed_id
      }
      this.renderEntry(entry)
      this.updateFinalizeButton()
    })
  }

  bindUploadProgress(request, entry) {
    request.upload.addEventListener("progress", (event) => {
      if (!event.lengthComputable) return

      entry.progress = Math.round((event.loaded / event.total) * 100)
      this.renderEntry(entry)
    })
  }

  validateFile(file) {
    if (this.maxFileSizeValue && file.size > this.maxFileSizeValue) return "invalid"
    const allowed = this.allowedContentTypePatterns()
    if (allowed.length > 0 && !allowed.some((pattern) => this.matchesContentType(pattern, file.type))) return "invalid"
    return "pending"
  }

  validationError(file) {
    if (this.maxFileSizeValue && file.size > this.maxFileSizeValue) return "File exceeds the maximum allowed size"
    return `${file.type || "Unknown type"} is not allowed. Allowed types: ${this.allowedContentTypePatterns().join(", ")}`
  }

  maxFilesError() {
    const noun = this.maxFilesCountValue === 1 ? "file" : "files"
    return `You can upload up to ${this.maxFilesCountValue} ${noun} at a time`
  }

  matchesContentType(pattern, contentType) {
    if (pattern.endsWith("/*")) return contentType.startsWith(pattern.replace(/\*$/, ""))
    return pattern === contentType
  }

  allowedContentTypePatterns() {
    return (this.allowedContentTypesValue || "").split(",").map((value) => value.trim()).filter(Boolean)
  }

  queueableEntryCount() {
    return this.files.filter((entry) => entry.status !== "invalid").length
  }

  renderQueue() {
    this.queueTarget.innerHTML = ""
    if (this.files.length === 0) {
      this.queueTarget.appendChild(this.emptyStateTarget)
      this.emptyStateTarget.classList.remove("hidden")
      this.updateFinalizeButton()
      return
    }

    this.emptyStateTarget.classList.add("hidden")
    this.files.forEach((entry) => this.queueTarget.insertAdjacentHTML("beforeend", this.entryTemplate(entry)))
    this.updateFinalizeButton()
  }

  renderEntry(entry) {
    const node = this.queueTarget.querySelector(`[data-entry-id='${entry.id}']`)
    if (node) {
      node.outerHTML = this.entryTemplate(entry)
    } else {
      this.renderQueue()
    }
  }

  updateFinalizeButton() {
    this.finalizeButtonTarget.disabled = this.files.every((entry) => entry.status !== "uploaded")
  }

  entryTemplate(entry) {
    const preview = entry.previewUrl ? `<img src="${this.escapeAttribute(entry.previewUrl)}" alt="" class="h-12 w-12 rounded object-cover" />` : `<div class="flex h-12 w-12 items-center justify-center rounded bg-[var(--surface-muted-background-color)] text-xs">FILE</div>`
    const progress = entry.status === "uploading" || entry.progress > 0 ? `<progress class="w-full" value="${entry.progress}" max="100"></progress>` : ""
    const error = entry.error ? `<p class="text-xs text-red-600">${this.escapeHtml(entry.error)}</p>` : ""
    const retry = entry.status === "failed" ? `<button type="button" data-action="recording-studio-attachable--upload#retry" data-id="${entry.id}" class="text-xs underline">Retry</button>` : ""

    return `
      <div data-entry-id="${entry.id}" class="rounded-lg border border-[var(--surface-border-color)] p-4">
        <div class="flex items-start gap-4">
          ${preview}
          <div class="min-w-0 flex-1 space-y-2">
            <div>
              <p class="font-medium">${this.escapeHtml(entry.file.name)}</p>
              <p class="text-xs text-[var(--surface-muted-content-color)]">${Math.round(entry.file.size / 1024)} KB · ${entry.status}</p>
            </div>
            ${progress}
            ${error}
          </div>
          <div class="flex flex-col items-end gap-2">
            ${retry}
            <button type="button" data-action="recording-studio-attachable--upload#remove" data-id="${entry.id}" class="text-xs underline">Remove</button>
          </div>
        </div>
      </div>
    `
  }

  revokePreview(entry) {
    if (entry?.previewUrl) URL.revokeObjectURL(entry.previewUrl)
  }

  escapeHtml(value) {
    const div = document.createElement("div")
    div.textContent = String(value || "")
    return div.innerHTML
  }

  escapeAttribute(value) {
    return this.escapeHtml(value).replace(/"/g, "&quot;")
  }
}
