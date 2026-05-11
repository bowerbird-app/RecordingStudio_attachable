import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["attachments", "emptyState", "attachmentTemplate"]

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
    const previewHtml = this.interpolateTemplate(this.attachmentTemplateTarget.innerHTML, {
      ATTACHMENT_ID: attachment.id,
      ATTACHMENT_NAME: attachment.name || "Untitled image",
      ATTACHMENT_THUMBNAIL_URL: attachment.thumbnail_url || attachment.insert_url || "",
      ATTACHMENT_URL: attachment.insert_url || attachment.thumbnail_url || "",
      REMOVE_LABEL: `Remove ${attachment.name || "image"}`,
    })

    const wrapper = document.createElement("div")
    wrapper.innerHTML = previewHtml.trim()
    return wrapper.firstElementChild
  }

  interpolateTemplate(templateHtml, values) {
    return Object.entries(values).reduce((result, [key, value]) => {
      return result.replaceAll(`__${key}__`, this.escapeHtml(String(value)))
    }, templateHtml)
  }

  escapeHtml(value) {
    return value
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
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