import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"
import { getUploadProviderLauncher } from "controllers/recording_studio_attachable/provider_launchers"
import { preprocessImageFile, shouldPreprocessImageFile } from "controllers/recording_studio_attachable/image_preprocessing"
import "controllers/recording_studio_attachable/google_drive_picker_launcher"

export default class extends Controller {
  static targets = ["dropzone", "input", "queue"]
  static values = {
    directUploadUrl: String,
    finalizeUrl: String,
    maxFileSize: Number,
    maxFilesCount: Number,
    imageProcessingEnabled: Boolean,
    imageProcessingMaxWidth: Number,
    imageProcessingMaxHeight: Number,
    imageProcessingQuality: Number,
    removeButtonTemplate: String,
    allowedContentTypes: String
  }

  connect() {
    this.files = []
    this.finalizeRequestInFlight = false
    this.providerButtonsByKey = new Map()
    this.handleProviderMessage = this.handleProviderMessage.bind(this)
    this.bindDropzoneEvents()
    window.addEventListener("message", this.handleProviderMessage)
  }

  disconnect() {
    this.files.forEach((entry) => this.revokePreview(entry))
    window.removeEventListener("message", this.handleProviderMessage)
  }

  browse() {
    this.inputTarget.click()
  }

  async launchProvider(event) {
    const button = event.currentTarget
    const { providerKey, providerStrategy } = button.dataset
    if (providerKey) this.providerButtonsByKey.set(providerKey, button)

    if (providerStrategy === "modal_page") {
      this.openProviderModal(button)
      return
    }

    if (providerStrategy === "client_picker") {
      await this.launchClientPicker(button)
    }
  }

  openProviderModal(button) {
    const frameUrl = button.dataset.providerFrameUrl
    const modalId = button.dataset.providerModalId || button.dataset.modalId
    if (!frameUrl || !modalId) return

    const frame = document.querySelector(`[data-provider-modal-frame][data-provider-modal-id='${modalId}']`)
    if (!frame) return

    if (!frame.dataset.sourceUrl) {
      frame.dataset.sourceUrl = frameUrl
    }

    if (frame.getAttribute("src") !== frameUrl) {
      frame.setAttribute("src", frameUrl)
    }
  }

  async launchClientPicker(button) {
    const launcherName = button.dataset.providerLauncher
    const launcher = getUploadProviderLauncher(launcherName)
    if (!launcher) {
      this.setProviderStatus("This upload provider is not available on this page.", "error")
      return
    }

    this.clearProviderStatus()

    try {
      await launcher.launch({
        button,
        controller: this,
        providerKey: button.dataset.providerKey,
        bootstrapUrl: button.dataset.providerBootstrapUrl,
        importUrl: button.dataset.providerImportUrl
      })
    } catch (error) {
      this.setProviderStatus(error?.message || "Could not open the provider picker.", "error")
    }
  }

  filesSelected(event) {
    this.addFiles(Array.from(event.target.files || []))
    event.target.value = null
  }

  finalize() {
    if (this.finalizeRequestInFlight || !this.queueSettled()) return

    const readyEntries = this.uploadedEntries()
    if (readyEntries.length === 0) return

    this.finalizeRequestInFlight = true
    readyEntries.forEach((entry) => {
      entry.status = "finalizing"
      this.renderEntry(entry)
    })

    fetch(this.finalizeUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "",
        "X-Requested-With": "XMLHttpRequest",
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
      .finally(() => {
        this.finalizeRequestInFlight = false
        this.maybeFinalize()
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
      this.maybeFinalize()
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
        status: exceedsCount ? "invalid" : this.initialStatusFor(file),
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

  async uploadEntry(entry) {
    try {
      entry.status = "processing"
      this.renderEntry(entry)

      await this.preprocessEntryFile(entry)

      const validationError = this.validationError(entry.file)
      if (validationError) {
        entry.status = "invalid"
        entry.error = validationError
        this.renderEntry(entry)
        return
      }

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
        this.maybeFinalize()
      })
    } catch (error) {
      entry.status = "failed"
      entry.error = error?.message || "Could not prepare file for upload"
      this.renderEntry(entry)
    }
  }

  bindUploadProgress(request, entry) {
    request.upload.addEventListener("progress", (event) => {
      if (!event.lengthComputable) return

      entry.progress = Math.round((event.loaded / event.total) * 100)
      this.renderEntry(entry)
    })
  }

  initialStatusFor(file) {
    return this.initialValidationError(file) ? "invalid" : "pending"
  }

  validationError(file) {
    if (this.maxFileSizeValue && file.size > this.maxFileSizeValue) return "File exceeds the maximum allowed size"
    if (!this.contentTypeAllowed(file)) {
      return `${file.type || "Unknown type"} is not allowed. Allowed types: ${this.allowedContentTypePatterns().join(", ")}`
    }

    return null
  }

  initialValidationError(file) {
    if (this.deferSizeValidationUntilAfterProcessing(file)) {
      return this.contentTypeAllowed(file)
        ? null
        : `${file.type || "Unknown type"} is not allowed. Allowed types: ${this.allowedContentTypePatterns().join(", ")}`
    }

    return this.validationError(file)
  }

  deferSizeValidationUntilAfterProcessing(file) {
    return shouldPreprocessImageFile(file, this.imageProcessingOptions())
  }

  contentTypeAllowed(file) {
    const allowed = this.allowedContentTypePatterns()
    return allowed.length === 0 || allowed.some((pattern) => this.matchesContentType(pattern, file.type))
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
      this.queueTarget.classList.add("hidden")
      return
    }

    this.queueTarget.classList.remove("hidden")
    this.files.forEach((entry) => this.queueTarget.insertAdjacentHTML("beforeend", this.entryTemplate(entry)))
    this.maybeFinalize()
  }

  renderEntry(entry) {
    const node = this.queueTarget.querySelector(`[data-entry-id='${entry.id}']`)
    if (node) {
      const template = document.createElement("template")
      template.innerHTML = this.entryTemplate(entry).trim()

      const nextNode = template.content.firstElementChild
      const currentContent = node.querySelector("[data-entry-content]")
      const nextContent = nextNode?.querySelector("[data-entry-content]")

      if (currentContent && nextContent) {
        currentContent.replaceWith(nextContent)
      } else if (nextNode) {
        node.replaceWith(nextNode)
      }
    } else {
      this.renderQueue()
    }
  }

  handleProviderMessage(event) {
    if (event.origin !== window.location.origin) return

    const payload = event.data || {}
    if (payload.namespace !== "recording-studio-attachable") return

    if (payload.type === "provider-auth-complete") {
      if (payload.modalId) {
        this.reloadProviderFrame(payload)
        return
      }

      if (payload.providerKey) {
        this.relaunchProvider(payload.providerKey)
      }
      return
    }

    if (payload.type === "provider-auth-error") {
      this.setProviderStatus(payload.error || "Authentication failed.", "error")
      return
    }

    if (payload.type === "provider-import-complete") {
      this.closeProviderModal(payload.modalId)
      if (payload.redirectPath) {
        window.location.href = payload.redirectPath
      }
    }
  }

  relaunchProvider(providerKey) {
    const button = this.providerButtonsByKey.get(providerKey)
    if (!button) return

    this.launchClientPicker(button)
  }

  reloadProviderFrame(payload) {
    const frame = document.querySelector(`[data-provider-modal-frame][data-provider-modal-id='${payload.modalId}']`)
    if (!frame) return

    const nextUrl = payload.reloadUrl || frame.dataset.sourceUrl || frame.getAttribute("src")
    if (!nextUrl) return

    frame.dataset.sourceUrl = nextUrl
    frame.setAttribute("src", nextUrl)
  }

  closeProviderModal(modalId) {
    if (!modalId) return

    const modal = document.getElementById(modalId)
    if (!modal) return

    const controller = this.application.getControllerForElementAndIdentifier(modal, "flat-pack--modal")
    if (controller) {
      controller.close()
    }
  }

  async fetchProviderBootstrap(bootstrapUrl) {
    const response = await fetch(bootstrapUrl, {
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    const payload = await response.json()
    if (!response.ok) throw new Error(payload.error || "Could not load provider bootstrap data.")

    return payload
  }

  async submitProviderImport(importUrl, fileIds) {
    const response = await fetch(importUrl, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "",
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ file_ids: fileIds })
    })
    const payload = await response.json()
    if (!response.ok) throw new Error(payload.error || "Could not import selected files.")

    return payload
  }

  openPopup(url, name = "recording-studio-attachable-provider-auth") {
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

    const popup = window.open(url, name, features)
    if (popup) popup.focus()
    return popup
  }

  setProviderStatus(message, kind = "info") {
    let region = this.element.querySelector("[data-provider-status-region]")
    if (!region) {
      region = document.createElement("p")
      region.dataset.providerStatusRegion = "true"
      region.className = "text-sm"
      const anchor = this.element.querySelector(".max-w-sm")
      if (anchor) {
        anchor.insertAdjacentElement("afterend", region)
      } else {
        this.element.appendChild(region)
      }
    }

    region.textContent = message
    region.classList.remove("hidden", "text-red-600", "text-(--surface-muted-content-color)")
    region.classList.add(kind === "error" ? "text-red-600" : "text-(--surface-muted-content-color)")
  }

  clearProviderStatus() {
    const region = this.element.querySelector("[data-provider-status-region]")
    if (!region) return

    region.textContent = ""
    region.classList.add("hidden")
  }

  maybeFinalize() {
    if (this.finalizeRequestInFlight || !this.queueSettled()) return
    if (this.uploadedEntries().length === 0) return

    this.finalize()
  }

  uploadedEntries() {
    return this.files.filter((entry) => entry.status === "uploaded")
  }

  queueSettled() {
    return this.files.every((entry) => !["pending", "processing", "uploading", "finalizing"].includes(entry.status))
  }

  async preprocessEntryFile(entry) {
    const result = await preprocessImageFile(entry.file, this.imageProcessingOptions())
    if (!result.transformed) return

    this.revokePreview(entry)
    entry.file = result.file
    entry.previewUrl = entry.file.type.startsWith("image/") ? URL.createObjectURL(entry.file) : null
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

  entryTemplate(entry) {
    const preview = entry.previewUrl ? `<img src="${this.escapeAttribute(entry.previewUrl)}" alt="" class="h-12 w-12 rounded object-cover" />` : `<div class="flex h-12 w-12 items-center justify-center rounded bg-(--surface-muted-background-color) text-xs">FILE</div>`
    const progress = entry.status === "processing"
      ? `<p class="text-xs text-(--surface-muted-content-color)">Optimizing image before upload…</p>`
      : entry.status === "uploading" || entry.progress > 0
        ? `<progress class="w-full" value="${entry.progress}" max="100"></progress>`
        : ""
    const error = entry.error ? `<p class="text-xs text-red-600">${this.escapeHtml(entry.error)}</p>` : ""
    const retry = entry.status === "failed" ? `<button type="button" data-action="recording-studio-attachable--upload#retry" data-id="${entry.id}" class="text-xs underline">Retry</button>` : ""
    const remove = this.removeButtonTemplateValue
      .replace("__ENTRY_ID__", this.escapeAttribute(entry.id))
      .replace("__REMOVE_LABEL__", this.escapeAttribute(`Remove ${entry.file.name} from upload queue`))
      .replace("__REMOVE_TITLE__", this.escapeAttribute("Remove from upload queue"))

    return `
      <div data-entry-id="${entry.id}" class="relative rounded-lg border border-(--surface-border-color) p-4 pr-12">
        ${remove}
        <div data-entry-content class="flex items-start gap-4">
          ${preview}
          <div class="min-w-0 flex-1 space-y-2">
            <div>
              <p class="font-medium">${this.escapeHtml(entry.file.name)}</p>
              <p class="text-xs text-(--surface-muted-content-color)">${Math.round(entry.file.size / 1024)} KB · ${entry.status}</p>
            </div>
            ${progress}
            ${error}
          </div>
          <div class="flex flex-col items-end gap-2 pt-6">
            ${retry}
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
