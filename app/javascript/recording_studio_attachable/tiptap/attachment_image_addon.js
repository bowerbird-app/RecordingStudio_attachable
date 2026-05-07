import { mergeAttributes } from "@tiptap/core"
import { Image } from "@tiptap/extension-image"
import { registerTiptapAddon } from "flat_pack/tiptap/addon_registry"

const IMAGE_ICON = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>`

const DISPLAY_WIDTHS = {
  small: "33%",
  medium: "50%",
  full: "100%",
}

function selectedImage(state) {
  const { selection } = state

  if (selection?.node?.type?.name !== "image") {
    return null
  }

  return { pos: selection.from, node: selection.node }
}

function imageStyle(attrs = {}) {
  const width = DISPLAY_WIDTHS[attrs.display] || DISPLAY_WIDTHS.medium
  const align = attrs.align || "center"

  let marginLeft = "0"
  let marginRight = "0"

  if (align === "center") {
    marginLeft = "auto"
    marginRight = "auto"
  } else if (align === "right") {
    marginLeft = "auto"
  }

  return [
    `width:${width}`,
    "max-width:100%",
    "height:auto",
    "display:block",
    `margin-left:${marginLeft}`,
    `margin-right:${marginRight}`,
  ].join(";")
}

function controlButton({ label, isActive = false, onMouseDown }) {
  const button = document.createElement("button")
  button.type = "button"
  button.textContent = label
  button.setAttribute("aria-pressed", isActive ? "true" : "false")
  button.style.cssText = [
    "border:1px solid var(--surface-border-color)",
    `background:${isActive ? "var(--surface-muted-background-color)" : "var(--surface-background-color)"}`,
    "color:var(--surface-content-color)",
    "border-radius:9999px",
    "padding:0.2rem 0.55rem",
    "font-size:0.75rem",
    "line-height:1.2",
    "cursor:pointer",
  ].join(";")
  button.addEventListener("mousedown", (event) => {
    event.preventDefault()
    onMouseDown(event)
  })
  return button
}

function applyButtonState(button, isActive) {
  button.setAttribute("aria-pressed", isActive ? "true" : "false")
  button.style.background = isActive
    ? "var(--surface-muted-background-color)"
    : "var(--surface-background-color)"
}

function controlsRow() {
  const row = document.createElement("div")
  row.style.cssText = [
    "display:flex",
    "flex-wrap:wrap",
    "align-items:center",
    "gap:0.35rem",
  ].join(";")
  return row
}

const ManagedAttachmentImage = Image.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      attachmentId: {
        default: null,
        parseHTML: (element) => element.getAttribute("data-attachment-id"),
        renderHTML: (attributes) => {
          if (!attributes.attachmentId) return {}
          return { "data-attachment-id": attributes.attachmentId }
        },
      },
      showPath: {
        default: null,
        parseHTML: (element) => element.getAttribute("data-show-path"),
        renderHTML: (attributes) => {
          if (!attributes.showPath) return {}
          return { "data-show-path": attributes.showPath }
        },
      },
      display: {
        default: "medium",
        parseHTML: (element) => element.getAttribute("data-display") || "medium",
        renderHTML: (attributes) => ({ "data-display": attributes.display || "medium" }),
      },
      align: {
        default: "center",
        parseHTML: (element) => element.getAttribute("data-align") || "center",
        renderHTML: (attributes) => ({ "data-align": attributes.align || "center" }),
      },
    }
  },

  renderHTML({ HTMLAttributes }) {
    return ["img", mergeAttributes(this.options.HTMLAttributes, HTMLAttributes, { style: imageStyle(HTMLAttributes) })]
  },

  addCommands() {
    return {
      updateAttachmentImageAttrs: (attrs = {}) => ({ state, dispatch }) => {
        const image = selectedImage(state)
        if (!image) return false

        dispatch(state.tr.setNodeMarkup(image.pos, undefined, { ...image.node.attrs, ...attrs }))
        return true
      },

      removeSelectedAttachmentImage: () => ({ state, dispatch }) => {
        if (!selectedImage(state)) return false

        dispatch(state.tr.deleteSelection())
        return true
      },
    }
  },

  addNodeView() {
    return ({ node, editor, getPos }) => {
      const wrapper = document.createElement("div")
      const image = document.createElement("img")
      const toolbar = document.createElement("div")
      const altPopover = document.createElement("div")
      const altInput = document.createElement("input")
      const altSave = document.createElement("button")
      const sizeButtons = new Map()
      const alignButtons = new Map()

      wrapper.style.cssText = [
        "position:relative",
        "margin:1rem 0",
      ].join(";")

      toolbar.style.cssText = [
        "position:absolute",
        "top:0.75rem",
        "left:50%",
        "transform:translateX(-50%)",
        "z-index:10",
        "display:none",
        "flex-direction:column",
        "gap:0.4rem",
        "min-width:min(26rem, calc(100% - 1rem))",
        "padding:0.55rem",
        "border:1px solid var(--surface-border-color)",
        "border-radius:0.85rem",
        "background:color-mix(in srgb, var(--surface-background-color) 92%, white 8%)",
        "box-shadow:0 12px 32px rgba(15, 23, 42, 0.16)",
      ].join(";")

      altPopover.style.cssText = "display:none;align-items:center;gap:0.35rem;"
      altInput.type = "text"
      altInput.placeholder = "Describe image"
      altInput.style.cssText = [
        "flex:1 1 auto",
        "min-width:10rem",
        "border:1px solid var(--surface-border-color)",
        "border-radius:9999px",
        "padding:0.35rem 0.75rem",
        "background:var(--surface-background-color)",
        "color:var(--surface-content-color)",
        "font-size:0.75rem",
      ].join(";")
      altSave.type = "button"
      altSave.textContent = "Save"
      altSave.style.cssText = [
        "border:none",
        "border-radius:9999px",
        "padding:0.35rem 0.75rem",
        "background:var(--surface-content-color)",
        "color:var(--surface-background-color)",
        "font-size:0.75rem",
        "cursor:pointer",
      ].join(";")
      altPopover.appendChild(altInput)
      altPopover.appendChild(altSave)

      const render = (currentNode) => {
        image.src = currentNode.attrs.src || ""
        image.alt = currentNode.attrs.alt || ""
        image.title = currentNode.attrs.title || ""
        image.setAttribute("data-attachment-id", currentNode.attrs.attachmentId || "")
        image.setAttribute("data-show-path", currentNode.attrs.showPath || "")
        image.setAttribute("data-display", currentNode.attrs.display || "medium")
        image.setAttribute("data-align", currentNode.attrs.align || "center")
        image.style.cssText = imageStyle(currentNode.attrs)
        image.className = toolbar.style.display === "none" ? "" : "is-selected"
        altInput.value = currentNode.attrs.alt || ""

        sizeButtons.forEach((button, value) => applyButtonState(button, currentNode.attrs.display === value))
        alignButtons.forEach((button, value) => applyButtonState(button, currentNode.attrs.align === value))
      }

      const updateAttrs = (attrs) => {
        const pos = getPos()
        if (typeof pos !== "number") return

        const currentNode = editor.state.doc.nodeAt(pos)
        if (!currentNode || currentNode.type.name !== "image") return

        const transaction = editor.state.tr.setNodeMarkup(pos, undefined, { ...currentNode.attrs, ...attrs })

        editor.view.dispatch(transaction)
        editor.commands.focus()
      }

      const removeImage = () => {
        const pos = getPos()
        if (typeof pos !== "number") return

        const currentNode = editor.state.doc.nodeAt(pos)
        if (!currentNode || currentNode.type.name !== "image") return

        const transaction = editor.state.tr.delete(pos, pos + currentNode.nodeSize)

        editor.view.dispatch(transaction)
        editor.commands.focus()
      }

      const sizeRow = controlsRow()
      const alignRow = controlsRow()
      const actionRow = controlsRow()

      ;[
        ["S", "small"],
        ["M", "medium"],
        ["Full", "full"],
      ].forEach(([label, value]) => {
        const button = controlButton({
          label,
          isActive: node.attrs.display === value,
          onMouseDown: () => updateAttrs({ display: value }),
        })
        sizeButtons.set(value, button)
        sizeRow.appendChild(button)
      })

      ;[
        ["Left", "left"],
        ["Center", "center"],
        ["Right", "right"],
      ].forEach(([label, value]) => {
        const button = controlButton({
          label,
          isActive: node.attrs.align === value,
          onMouseDown: () => updateAttrs({ align: value }),
        })
        alignButtons.set(value, button)
        alignRow.appendChild(button)
      })

      actionRow.appendChild(controlButton({
        label: "Alt",
        onMouseDown: () => {
          altPopover.style.display = altPopover.style.display === "none" ? "flex" : "none"
          if (altPopover.style.display === "flex") {
            altInput.focus()
            altInput.select()
          }
        },
      }))

      actionRow.appendChild(controlButton({
        label: "Remove",
        onMouseDown: removeImage,
      }))

      altSave.addEventListener("mousedown", (event) => {
        event.preventDefault()
        updateAttrs({ alt: altInput.value.trim() })
        altPopover.style.display = "none"
      })

      altInput.addEventListener("keydown", (event) => {
        if (event.key === "Enter") {
          event.preventDefault()
          updateAttrs({ alt: altInput.value.trim() })
          altPopover.style.display = "none"
        }

        if (event.key === "Escape") {
          event.preventDefault()
          altPopover.style.display = "none"
          editor.commands.focus()
        }
      })

      toolbar.appendChild(sizeRow)
      toolbar.appendChild(alignRow)
      toolbar.appendChild(actionRow)
      toolbar.appendChild(altPopover)
      wrapper.appendChild(toolbar)
      wrapper.appendChild(image)

      render(node)

      return {
        dom: wrapper,

        update(updatedNode) {
          if (updatedNode.type.name !== "image") return false
          render(updatedNode)
          return true
        },

        selectNode() {
          toolbar.style.display = "flex"
          image.style.outline = "2px solid var(--surface-content-color)"
          image.style.outlineOffset = "4px"
        },

        deselectNode() {
          toolbar.style.display = "none"
          altPopover.style.display = "none"
          image.style.outline = "none"
          image.style.outlineOffset = "0"
        },

        stopEvent(event) {
          return toolbar.contains(event.target) || altPopover.contains(event.target)
        },

        ignoreMutation() {
          return true
        },
      }
    }
  },
})

registerTiptapAddon("attachment_image", {
  extensions: () => [ManagedAttachmentImage],
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