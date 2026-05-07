import { registerTiptapAddon } from "flat_pack/tiptap/addon_registry"

const HTML_ICON = '<span aria-hidden="true" style="font-size:11px;font-weight:700;line-height:1">HTML</span>'

registerTiptapAddon("html_preview", {
  toolbarTools: ({ addonOptions }) => [
    {
      name: "htmlPreview",
      label: addonOptions.label || "View HTML",
      icon: HTML_ICON,
      action: (editor) => {
        editor.view.dom.dispatchEvent(new CustomEvent(addonOptions.eventName || "flat-pack:html-preview", {
          bubbles: true,
          detail: { editor }
        }))
      },
      isDisabled: (editor) => !editor.isEditable
    }
  ]
})