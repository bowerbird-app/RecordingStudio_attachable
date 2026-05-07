import { registerTiptapAddon } from "flat_pack/tiptap/addon_registry"

const IMAGE_ICON = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>`

registerTiptapAddon("attachment_image", {
  toolbarTools: ({ addonOptions }) => [
    {
      name: "attachmentImage",
      label: addonOptions.label || "Insert image",
      icon: IMAGE_ICON,
      action: (editor) => {
        editor.view.dom.dispatchEvent(new CustomEvent(addonOptions.eventName || "flat-pack:attachment-image-picker", {
          bubbles: true,
          detail: { editor }
        }))
      },
      isDisabled: (editor) => !editor.isEditable
    }
  ]
})