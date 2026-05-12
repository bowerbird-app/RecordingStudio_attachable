import { DirectUpload } from "@rails/activestorage"
import { Controller } from "@hotwired/stimulus"
import { application } from "controllers/application"
import { getUploadProviderLauncher } from "controllers/recording_studio_attachable/provider_launchers"
import { preprocessImageFile } from "controllers/recording_studio_attachable/image_preprocessing"
import "controllers/recording_studio_attachable/google_drive_picker_launcher"

const PROVIDER_EVENT_STORAGE_KEY = "recording-studio-attachable:provider-event"
const PROVIDER_EVENT_CHANNEL_NAME = `${PROVIDER_EVENT_STORAGE_KEY}:channel`

export default class extends Controller {
  static targets = [
    "editorHost",
    "searchInput",
    "fileInput",
    "status",
    "uploadQueue",
    "progressTemplate",
    "modeSummary",
    "scrollContainer",
    "gallery",
    "emptyState",
    "selectionActions",
    "selectionCount",
    "confirmButton",
  ]

  static values = {
    pickerUrl: String,
    uploadUrl: String,
    directUploadUrl: String,
    modalId: String,
    multipleSelection: Boolean,
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
    this.selectedAttachments = new Map()
    this.uploadEntries = []
    this.providerUploadTimers = new Map()
    this.providerButtonsByKey = new Map()
    this.boundHandleScroll = this.handleScroll.bind(this)
    this.handleProviderMessage = this.handleProviderMessage.bind(this)
    this.handleProviderStorage = this.handleProviderStorage.bind(this)
    this.handleProviderChannelMessage = this.handleProviderChannelMessage.bind(this)

    this.syncFileInputMode()
    this.updateSelectionUi()
    window.addEventListener("message", this.handleProviderMessage)
    window.addEventListener("storage", this.handleProviderStorage)

    if (window.BroadcastChannel) {
      this.providerEventChannel = new window.BroadcastChannel(PROVIDER_EVENT_CHANNEL_NAME)
      this.providerEventChannel.addEventListener("message", this.handleProviderChannelMessage)
    }

    if (this.hasScrollContainerTarget) {
      this.scrollContainerTarget.addEventListener("scroll", this.boundHandleScroll)
    }
  }

  disconnect() {
    if (this.searchTimeoutId) {
      window.clearTimeout(this.searchTimeoutId)
      this.searchTimeoutId = null
    }

    this.clearProviderUploadTimers()

    window.removeEventListener("message", this.handleProviderMessage)
    window.removeEventListener("storage", this.handleProviderStorage)

    if (this.providerEventChannel) {
      this.providerEventChannel.removeEventListener("message", this.handleProviderChannelMessage)
      this.providerEventChannel.close()
      this.providerEventChannel = null
    }

    if (this.hasScrollContainerTarget) {
      this.scrollContainerTarget.removeEventListener("scroll", this.boundHandleScroll)
    }
  }

  openPicker(event) {
    if (event) event.preventDefault()

    this.activeEditor = null
    this.openModalAndLoad()
  }

  openSinglePicker(event) {
    if (event) {
      event.preventDefault()
      this.closeModeMenu(event)
    }

    this.activeEditor = null
    this.setMultipleSelectionMode(false)
    this.openModalAndLoad()
  }

  openMultiplePicker(event) {
    if (event) {
      event.preventDefault()
      this.closeModeMenu(event)
    }

    this.activeEditor = null
    this.setMultipleSelectionMode(true)
    this.openModalAndLoad()
  }

  async launchProvider(event) {
    if (event) event.preventDefault()

    const button = event.currentTarget
    const { providerKey, providerStrategy } = button.dataset
    if (providerKey) this.providerButtonsByKey.set(providerKey, button)

    if (providerStrategy === "client_picker") {
      await this.launchClientPicker(button)
    }
  }

  async launchClientPicker(button) {
    const launcherName = button.dataset.providerLauncher
    const launcher = getUploadProviderLauncher(launcherName)
    if (!launcher) {
      this.showStatus("This upload provider is not available on this page.")
      return
    }

    this.showStatus("")

    try {
      await launcher.launch({
        button,
        controller: this,
        providerKey: button.dataset.providerKey,
        bootstrapUrl: button.dataset.providerBootstrapUrl,
        importUrl: button.dataset.providerImportUrl
      })
    } catch (error) {
      this.showStatus(error?.message || "Could not open the provider picker.")
    }
  }

  openPickerFromToolbar(event) {
    event.preventDefault()

    this.activeEditor = event.detail?.editor || this.editorController()?.editor || null
    this.setMultipleSelectionMode(false)
    this.openModalAndLoad()
  }

  browseUpload(event) {
    if (event) event.preventDefault()

    this.syncFileInputMode()
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
    const files = Array.from(this.fileInputTarget.files || [])
    if (files.length === 0) return

    const selectedFiles = this.multipleSelectionEnabled() ? files : [files[0]]
    this.directUploadFiles(selectedFiles)
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

  selectAttachment(attachment) {
    if (this.multipleSelectionEnabled()) {
      this.toggleAttachmentSelection(attachment)
      return
    }

    this.dispatchSelection(attachment)
    this.modalController()?.close?.()
  }

  confirmSelection() {
    if (!this.multipleSelectionEnabled() || this.selectedAttachments.size === 0) return

    this.selectedAttachments.forEach((attachment) => this.dispatchSelection(attachment))
    this.clearSelection()
    this.modalController()?.close?.()
  }

  clearSelection() {
    if (this.selectedAttachments.size === 0) return

    this.selectedAttachments.clear()
    this.updateSelectionUi()
    this.refreshGallerySelection()
  }

  dispatchSelection(attachment) {
    this.dispatch("selected", { detail: { attachment } })

    this.insertAttachment(attachment)
  }

  insertAttachment(attachment) {
    const editor = this.activeEditor || this.editorController()?.editor
    if (editor) {
      const variantUrls = attachment.variant_urls || {}
      const originalSrc = attachment.insert_url
      const smallSrc = variantUrls.small || originalSrc
      const mediumSrc = variantUrls.medium || originalSrc
      const largeSrc = variantUrls.large || originalSrc

      editor.chain().focus().setImage({
        src: smallSrc,
        alt: attachment.alt || attachment.name,
        attachmentId: attachment.id,
        showPath: attachment.show_path,
        originalSrc,
        smallSrc,
        mediumSrc,
        largeSrc,
        display: "small",
        align: "left",
      }).run()
    }
  }

  openModalAndLoad() {
    this.modalController()?.open?.()
    this.currentPage = 1
    this.clearSelection()
    this.clearUploadQueue()
    this.loadAttachments({ reset: true })
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

  async directUploadFiles(files) {
    const attachments = []
    this.uploadEntries = files.map((file) => this.buildUploadEntry(file))
    this.renderUploadQueue()

    try {
      for (const [index, file] of files.entries()) {
        const entry = this.uploadEntries[index]
        if (entry) {
          entry.status = "processing"
          this.renderUploadEntry(entry)
        }

        const processed = await preprocessImageFile(file, this.imageProcessingOptions())
        const uploadFile = processed.file
        if (entry) {
          entry.file = uploadFile
          entry.name = uploadFile.name
          entry.status = "uploading"
          entry.progress = 0
          entry.processingComplete = processed.transformed
          this.renderUploadEntry(entry)
        }
        const statusPrefix = files.length > 1 ? `Uploading ${index + 1} of ${files.length}` : "Uploading"
        this.showStatus(
          processed.transformed ? `Optimizing complete. ${statusPrefix}: ${uploadFile.name}…` : `${statusPrefix}: ${uploadFile.name}…`
        )

        const blob = await this.directUploadBlob(uploadFile, entry)
        if (entry) {
          entry.status = "uploaded"
          entry.progress = 100
          this.renderUploadEntry(entry)
        }
        attachments.push({
          signed_blob_id: blob.signed_id,
          name: this.defaultAttachmentName(uploadFile)
        })
      }

      const createdAttachments = await this.createAttachments(attachments)

      createdAttachments.forEach((attachment) => this.dispatchSelection(attachment))

      const noun = createdAttachments.length === 1 ? "image" : "images"
      this.showStatus(`Added ${createdAttachments.length} ${noun}`)
      this.currentPage = 1
      this.clearSelection()
      this.clearUploadQueue()
      this.loadAttachments({ reset: true })
      this.modalController()?.close?.()
    } catch (uploadError) {
      const failedEntry = this.uploadEntries.find((entry) => ["processing", "uploading"].includes(entry.status))
      if (failedEntry) {
        failedEntry.status = "failed"
        failedEntry.error = uploadError.message || "Unable to add image"
        this.renderUploadEntry(failedEntry)
      }
      this.showStatus(uploadError.message || "Unable to add image")
    } finally {
      this.fileInputTarget.value = ""
    }
  }

  async addProviderSelections(providerKey, selections) {
    const attachments = Array.from(selections || []).map((selection) => ({
      provider_key: providerKey,
      provider_payload: this.normalizedProviderPayload(selection),
      name: selection.name || selection.id || "Remote file",
      description: selection.description || ""
    }))

    this.uploadEntries = Array.from(selections || []).map((selection) => this.buildProviderUploadEntry(selection))
    this.renderUploadQueue()
    this.startProviderUploadSimulation()

    try {
      const createdAttachments = await this.createAttachments(attachments, providerKey)
      this.clearProviderUploadTimers()

      this.uploadEntries.forEach((entry) => {
        entry.status = "uploaded"
        entry.progress = 100
        this.renderUploadEntry(entry)
      })

      createdAttachments.forEach((attachment) => this.dispatchSelection(attachment))

      const noun = createdAttachments.length === 1 ? "image" : "images"
      this.showStatus(`Added ${createdAttachments.length} ${noun}`)
      this.currentPage = 1
      this.clearSelection()
      this.clearUploadQueue()
      this.loadAttachments({ reset: true })
      this.modalController()?.close?.()
    } catch (uploadError) {
      this.clearProviderUploadTimers()

      this.uploadEntries.forEach((entry) => {
        if (entry.status === "uploading") {
          entry.status = "failed"
          entry.error = uploadError.message || "Unable to add image"
          this.renderUploadEntry(entry)
        }
      })

      this.showStatus(uploadError.message || "Unable to add image")
    }
  }

  directUploadBlob(file, entry = null) {
    return new Promise((resolve, reject) => {
      const upload = new DirectUpload(file, this.directUploadUrlValue, entry
        ? { directUploadWillStoreFileWithXHR: (request) => this.bindUploadProgress(request, entry) }
        : {})

      upload.create((error, blob) => {
        if (error) {
          reject(error)
          return
        }

        resolve(blob)
      })
    })
  }

  bindUploadProgress(request, entry) {
    request.upload.addEventListener("progress", (event) => {
      if (!event.lengthComputable) return

      entry.progress = Math.round((event.loaded / event.total) * 100)
      this.renderUploadEntry(entry)
    })
  }

  async createAttachments(attachments, providerKey = null) {
    const response = await fetch(this.uploadUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({
        attachment_import: {
          provider_key: providerKey,
          attachments
        }
      })
    })

    const payload = await response.json()
    if (!response.ok) {
      throw new Error(payload.error || "Unable to add image")
    }

    const createdAttachments = payload.attachments || []
    if (createdAttachments.length === 0) {
      throw new Error("Upload completed without an attachment payload")
    }

    return createdAttachments
  }

  handleProviderMessage(event) {
    if (event.origin !== window.location.origin) return

    this.handleProviderPayload(event.data || {})
  }

  handleProviderStorage(event) {
    if (event.key !== PROVIDER_EVENT_STORAGE_KEY || !event.newValue) return

    try {
      const parsed = JSON.parse(event.newValue)
      this.handleProviderPayload(parsed?.payload || {})
    } catch (_error) {
    }
  }

  handleProviderChannelMessage(event) {
    this.handleProviderPayload(event.data || {})
  }

  handleProviderPayload(payload) {
    if (payload.namespace !== "recording-studio-attachable") return

    if (payload.type === "provider-auth-complete") {
      if (payload.providerKey) {
        this.relaunchProvider(payload.providerKey)
      }
      return
    }

    if (payload.type === "provider-auth-error") {
      this.showStatus(payload.error || "Authentication failed.")
    }
  }

  relaunchProvider(providerKey) {
    const button = this.providerButtonsByKey.get(providerKey)
    if (!button) return

    this.launchClientPicker(button)
  }

  fetchProviderBootstrap(bootstrapUrl) {
    return fetch(bootstrapUrl, {
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "X-Requested-With": "XMLHttpRequest"
      }
    }).then(async (response) => {
      const payload = await response.json()
      if (!response.ok) throw new Error(payload.error || "Could not load provider bootstrap data.")

      return payload
    })
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

  setProviderStatus(message) {
    this.showStatus(message)
  }

  clearProviderStatus() {
    this.showStatus("")
  }

  normalizedProviderPayload(selection) {
    return {
      id: selection.id,
      resource_key: selection.resource_key || selection.resourceKey
    }
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
      button.className = this.galleryButtonClass(this.attachmentSelectedForMultiMode(attachment.id))
      button.setAttribute("aria-label", attachment.name || "Untitled image")
      button.setAttribute("aria-pressed", this.attachmentSelectedForMultiMode(attachment.id) ? "true" : "false")
      button.dataset.attachmentId = attachment.id
      button.addEventListener("click", () => this.selectAttachment(attachment))

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

  buildUploadEntry(file) {
    return {
      id: crypto.randomUUID(),
      file,
      name: file.name,
      progress: 0,
      status: "pending",
      error: null,
      processingComplete: false
    }
  }

  buildProviderUploadEntry(selection) {
    return {
      id: crypto.randomUUID(),
      name: selection.name || selection.id || "Remote file",
      progress: 12,
      status: "uploading",
      error: null,
      processingComplete: false
    }
  }

  startProviderUploadSimulation() {
    this.uploadEntries.forEach((entry, index) => {
      entry.progress = 12
      this.renderUploadEntry(entry)
      this.scheduleProviderUploadStep(entry, [32, 56, 78, 90], 320 + (index * 120))
    })
  }

  scheduleProviderUploadStep(entry, remainingSteps, delay = 320) {
    this.clearProviderUploadTimer(entry.id)
    if (remainingSteps.length === 0) return

    const timerId = window.setTimeout(() => {
      if (entry.status !== "uploading") return

      entry.progress = remainingSteps[0]
      this.renderUploadEntry(entry)
      this.scheduleProviderUploadStep(entry, remainingSteps.slice(1), 420)
    }, delay)

    this.providerUploadTimers.set(entry.id, timerId)
  }

  clearProviderUploadTimer(entryId) {
    const timerId = this.providerUploadTimers.get(entryId)
    if (!timerId) return

    window.clearTimeout(timerId)
    this.providerUploadTimers.delete(entryId)
  }

  clearProviderUploadTimers() {
    this.providerUploadTimers.forEach((timerId) => window.clearTimeout(timerId))
    this.providerUploadTimers.clear()
  }

  renderUploadQueue() {
    if (!this.hasUploadQueueTarget) return

    this.uploadQueueTarget.innerHTML = ""
    this.uploadQueueTarget.classList.toggle("hidden", this.uploadEntries.length === 0)
    this.uploadEntries.forEach((entry) => {
      this.uploadQueueTarget.insertAdjacentHTML("beforeend", this.uploadEntryTemplate(entry))
    })
  }

  renderUploadEntry(entry) {
    if (!this.hasUploadQueueTarget) return

    const node = this.uploadQueueTarget.querySelector(`[data-upload-entry-id='${entry.id}']`)
    if (!node) {
      this.renderUploadQueue()
      return
    }

    const template = document.createElement("template")
    template.innerHTML = this.uploadEntryTemplate(entry).trim()

    const nextNode = template.content.firstElementChild
    const currentContent = node.querySelector("[data-upload-entry-content]")
    const nextContent = nextNode?.querySelector("[data-upload-entry-content]")

    if (currentContent && nextContent) {
      currentContent.replaceWith(nextContent)
    } else if (nextNode) {
      node.replaceWith(nextNode)
    }
  }

  clearUploadQueue() {
    this.clearProviderUploadTimers()
    this.uploadEntries = []
    if (!this.hasUploadQueueTarget) return

    this.uploadQueueTarget.innerHTML = ""
    this.uploadQueueTarget.classList.add("hidden")
  }

  uploadEntryTemplate(entry) {
    const progress = entry.status === "processing"
      ? this.progressTemplateHtml({
          value: 0,
          label: `Uploading ${this.entryName(entry)}`,
          hideLabel: true
        })
      : entry.status === "uploading" || entry.progress > 0
        ? this.progressTemplateHtml({
            value: entry.progress,
            label: `Uploading ${this.entryName(entry)}`,
            hideLabel: true
          })
        : entry.status === "uploaded"
          ? this.progressTemplateHtml({
              value: 100,
              label: `${this.entryName(entry)} uploaded`,
              hideLabel: true
            })
          : ""
    const error = entry.error ? `<p class="text-xs text-red-600">${this.escapeHtml(entry.error)}</p>` : ""

    return `
      <div data-upload-entry-id="${entry.id}" class="rounded-xl border border-(--surface-border-color) bg-(--surface-muted-background-color) px-4 py-3">
        <div data-upload-entry-content class="space-y-2">
          ${progress}
          ${error}
        </div>
      </div>
    `
  }

  entryName(entry) {
    return entry.file?.name || entry.name || "Image"
  }

  progressTemplateHtml({ value = 0, max = 100, label = "Progress", hideLabel = false } = {}) {
    if (!this.hasProgressTemplateTarget) return ""

    const template = this.progressTemplateTarget.content.firstElementChild
    if (!template) return ""

    const nextNode = template.cloneNode(true)
    const normalizedValue = Number.isFinite(Number(value)) ? Math.max(0, Math.min(Number(value), Number(max) || 100)) : 0
    const normalizedMax = Number(max) > 0 ? Number(max) : 100
    const percentage = normalizedMax > 0 ? Math.min((normalizedValue / normalizedMax) * 100, 100) : 0
    const progressBar = nextNode.querySelector("[role='progressbar']")
    const labelNode = nextNode.querySelector(".text-sm.font-medium")
    const fillNode = progressBar?.firstElementChild

    if (progressBar) {
      progressBar.setAttribute("aria-valuenow", String(normalizedValue))
      progressBar.setAttribute("aria-valuemin", "0")
      progressBar.setAttribute("aria-valuemax", String(normalizedMax))
      progressBar.setAttribute("aria-label", label)
    }

    if (labelNode) {
      labelNode.textContent = label
      labelNode.classList.toggle("hidden", hideLabel)
      labelNode.setAttribute("aria-hidden", hideLabel ? "true" : "false")
    }

    if (fillNode) {
      fillNode.style.width = `${percentage}%`
    }

    return nextNode.outerHTML
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
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

  multipleSelectionEnabled() {
    return this.multipleSelectionValue
  }

  setMultipleSelectionMode(enabled) {
    this.multipleSelectionValue = enabled
    this.clearSelection()
    this.syncFileInputMode()
    this.updateSelectionUi()
  }

  syncFileInputMode() {
    if (!this.hasFileInputTarget) return

    this.fileInputTarget.multiple = this.multipleSelectionEnabled()
  }

  toggleAttachmentSelection(attachment) {
    if (this.selectedAttachments.has(attachment.id)) {
      this.selectedAttachments.delete(attachment.id)
    } else {
      this.selectedAttachments.set(attachment.id, attachment)
    }

    this.updateSelectionUi()
    this.refreshGallerySelection()
  }

  updateSelectionUi() {
    this.updateModeSummary()

    if (!this.multipleSelectionEnabled()) {
      if (this.hasSelectionActionsTarget) {
        this.selectionActionsTarget.classList.add("hidden")
      }

      return
    }

    if (this.hasSelectionActionsTarget) {
      this.selectionActionsTarget.classList.remove("hidden")
    }

    if (this.hasSelectionCountTarget) {
      const count = this.selectedAttachments.size
      this.selectionCountTarget.textContent = count > 0 ? `${count} selected` : "Select one or more"
    }

    if (this.hasConfirmButtonTarget) {
      this.confirmButtonTarget.disabled = this.selectedAttachments.size === 0
    }
  }

  refreshGallerySelection() {
    if (!this.hasGalleryTarget || !this.multipleSelectionEnabled()) return

    this.galleryTarget.querySelectorAll("button[data-attachment-id]").forEach((button) => {
      const selected = this.attachmentSelectedForMultiMode(button.dataset.attachmentId)
      button.className = this.galleryButtonClass(selected)
      button.setAttribute("aria-pressed", selected ? "true" : "false")
    })
  }

  attachmentSelectedForMultiMode(id) {
    return this.selectedAttachments.has(String(id)) || this.selectedAttachments.has(id)
  }

  galleryButtonClass(selected) {
    const baseClass = "group flex h-full flex-col overflow-hidden rounded-xl border bg-(--surface-background-color) text-left shadow-sm transition focus:outline-none focus-visible:ring-2 focus-visible:ring-ring"

    if (selected) {
      return `${baseClass} border-(--surface-content-color) ring-2 ring-inset ring-ring shadow-md`
    }

    return `${baseClass} border-(--surface-border-color) hover:shadow-md`
  }

  updateModeSummary() {
    if (!this.hasModeSummaryTarget) return

    this.modeSummaryTarget.textContent = ""
    this.modeSummaryTarget.classList.add("hidden")
  }

  closeModeMenu(event) {
    event.currentTarget.closest("details")?.removeAttribute("open")
  }
}