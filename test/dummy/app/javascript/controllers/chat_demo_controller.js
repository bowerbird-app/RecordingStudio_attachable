import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["attachments", "emptyState"]

  static values = {
    attachUrl: String,
    detachUrlTemplate: String,
  }

  connect() {
    this.toggleEmptyState()
  }

  async attachmentSelected(event) {
    const { attachment } = event.detail || {}
    if (!attachment || this.hasAttachment(attachment.id)) return

    await this.persistAttachment(attachment.id)
    this.attachmentsTarget.appendChild(this.buildPreview(attachment))
    this.toggleEmptyState()
  }

  async removeAttachment(event) {
    const id = event.currentTarget.dataset.id
    if (!id) return

    await this.removePersistedAttachment(id)

    this.attachmentsTarget
      .querySelectorAll(`[data-chat-demo-attachment-id="${CSS.escape(String(id))}"]`)
      .forEach((preview) => preview.remove())

    this.toggleEmptyState()
  }

  hasAttachment(id) {
    return this.attachmentsTarget.querySelector(`[data-chat-demo-attachment-id="${CSS.escape(String(id))}"]`) !== null
  }

  buildPreview(attachment) {
    const wrapper = document.createElement("div")
    wrapper.className = "flex items-center gap-3 rounded-xl border border-(--surface-border-color) bg-(--surface-background-color) px-3 py-2"
    wrapper.dataset.chatDemoAttachmentId = attachment.id

    const image = document.createElement("img")
    image.src = attachment.thumbnail_url || attachment.insert_url
    image.alt = attachment.alt || attachment.name || "Selected image"
    image.className = "h-12 w-12 rounded-lg object-cover"
    wrapper.appendChild(image)

    const copy = document.createElement("div")
    copy.className = "min-w-0 flex-1"

    const title = document.createElement("p")
    title.className = "truncate text-sm font-medium text-(--surface-content-color)"
    title.textContent = attachment.name || "Untitled image"
    copy.appendChild(title)

    const meta = document.createElement("p")
    meta.className = "text-xs text-(--surface-muted-content-color)"
    meta.textContent = "Ready to send"
    copy.appendChild(meta)

    wrapper.appendChild(copy)

    const button = document.createElement("button")
    button.type = "button"
    button.className = "inline-flex h-8 w-8 items-center justify-center rounded-full text-(--surface-muted-content-color) transition hover:bg-(--surface-muted-background-color) hover:text-(--surface-content-color)"
    button.dataset.action = "chat-demo#removeAttachment"
    button.dataset.id = attachment.id
    button.setAttribute("aria-label", `Remove ${attachment.name || "image"}`)
    button.textContent = "×"
    wrapper.appendChild(button)

    return wrapper
  }

  async persistAttachment(id) {
    const response = await fetch(this.attachUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
      },
      body: JSON.stringify({ attachment_recording_id: id }),
    })

    if (!response.ok) {
      throw new Error("Unable to attach image to the draft message")
    }
  }

  async removePersistedAttachment(id) {
    const response = await fetch(this.detachUrlFor(id), {
      method: "DELETE",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken(),
      },
    })

    if (!response.ok) {
      throw new Error("Unable to remove image from the draft message")
    }
  }

  detachUrlFor(id) {
    return this.detachUrlTemplateValue.replace("__ATTACHMENT_ID__", encodeURIComponent(String(id)))
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  toggleEmptyState() {
    const empty = this.attachmentsTarget.childElementCount === 0
    this.emptyStateTarget.classList.toggle("hidden", !empty)
    this.attachmentsTarget.classList.toggle("hidden", empty)
  }
}