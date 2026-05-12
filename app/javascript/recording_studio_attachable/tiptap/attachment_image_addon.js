import { mergeAttributes } from "@tiptap/core"
import { Image } from "@tiptap/extension-image"
import { registerTiptapAddon } from "flat_pack/tiptap/addon_registry"

const IMAGE_ICON = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>`
const ALIGN_LEFT_ICON = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><line x1="4" y1="6" x2="20" y2="6"/><line x1="4" y1="10" x2="14" y2="10"/><line x1="4" y1="14" x2="20" y2="14"/><line x1="4" y1="18" x2="12" y2="18"/></svg>`
const ALIGN_CENTER_ICON = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><line x1="4" y1="6" x2="20" y2="6"/><line x1="7" y1="10" x2="17" y2="10"/><line x1="4" y1="14" x2="20" y2="14"/><line x1="8" y1="18" x2="16" y2="18"/></svg>`
const ALIGN_RIGHT_ICON = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><line x1="4" y1="6" x2="20" y2="6"/><line x1="10" y1="10" x2="20" y2="10"/><line x1="4" y1="14" x2="20" y2="14"/><line x1="12" y1="18" x2="20" y2="18"/></svg>`
const REMOVE_ICON = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><line x1="6" y1="6" x2="18" y2="18"/><line x1="18" y1="6" x2="6" y2="18"/></svg>`

const DISPLAY_WIDTHS = {
  small: "33%",
  medium: "50%",
  large: "100%",
  full: "100%",
}

const DISPLAY_SRC_ATTRS = {
  small: "smallSrc",
  medium: "mediumSrc",
  large: "largeSrc",
  full: "largeSrc",
}

function normalizedDisplay(display) {
  return display === "full" ? "large" : (display || "medium")
}

function selectedImage(state) {
  const { selection } = state

  if (selection?.node?.type?.name !== "image") {
    return null
  }

  return { pos: selection.from, node: selection.node }
}

function imageStyle(attrs = {}) {
  const width = DISPLAY_WIDTHS[normalizedDisplay(attrs.display)] || DISPLAY_WIDTHS.medium
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

function imageSrcForDisplay(attrs = {}, display) {
  const nextDisplay = normalizedDisplay(display || attrs.display)
  const srcAttr = DISPLAY_SRC_ATTRS[nextDisplay]

  return attrs[srcAttr] || attrs.originalSrc || attrs.src || ""
}

function controlButton({ label, icon, isActive = false, onMouseDown }) {
  const button = document.createElement("button")
  button.type = "button"
  if (icon) {
    button.innerHTML = icon
    button.setAttribute("aria-label", label)
    button.style.minWidth = "1.95rem"
    button.style.display = "inline-flex"
    button.style.alignItems = "center"
    button.style.justifyContent = "center"
  } else {
    button.textContent = label
  }
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

function tooltipClasses() {
  return [
    "fixed",
    "z-50",
    "hidden",
    "px-[var(--tooltip-padding-x)]",
    "py-[var(--tooltip-padding-y)]",
    "text-[length:var(--tooltip-font-size)]",
    "leading-snug",
    "font-medium",
    "text-[var(--tooltip-text-color)]",
    "bg-[var(--tooltip-background-color)]",
    "border",
    "border-[var(--tooltip-border-color)]",
    "rounded-[var(--tooltip-radius)]",
    "shadow-[var(--tooltip-shadow)]",
    "max-w-[var(--tooltip-max-width)]",
    "whitespace-normal",
    "break-words",
    "pointer-events-none",
    "opacity-0",
    "transition-opacity",
    "duration-200",
  ].join(" ")
}

function withTooltip(element, text, placement = "top") {
  const container = document.createElement("div")
  const tooltip = document.createElement("div")

  container.className = "relative inline-flex"
  container.dataset.controller = "flat-pack--tooltip"
  container.dataset.action = "mouseenter->flat-pack--tooltip#show mouseleave->flat-pack--tooltip#hide focusin->flat-pack--tooltip#show focusout->flat-pack--tooltip#hide"
  container.dataset.flatPackTooltipPlacementValue = placement

  tooltip.setAttribute("role", "tooltip")
  tooltip.className = tooltipClasses()
  tooltip.style.cssText = "background-color: var(--tooltip-background-color, var(--surface-content-color)); color: var(--tooltip-text-color, var(--surface-background-color)); border-color: var(--tooltip-border-color, var(--surface-border-color));"
  tooltip.dataset.flatPackTooltipTarget = "tooltip"
  tooltip.textContent = text

  container.appendChild(element)
  container.appendChild(tooltip)

  return container
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
      originalSrc: {
        default: null,
        parseHTML: (element) => element.getAttribute("data-original-src"),
        renderHTML: (attributes) => {
          if (!attributes.originalSrc) return {}
          return { "data-original-src": attributes.originalSrc }
        },
      },
      smallSrc: {
        default: null,
        parseHTML: (element) => element.getAttribute("data-small-src"),
        renderHTML: (attributes) => {
          if (!attributes.smallSrc) return {}
          return { "data-small-src": attributes.smallSrc }
        },
      },
      mediumSrc: {
        default: null,
        parseHTML: (element) => element.getAttribute("data-medium-src"),
        renderHTML: (attributes) => {
          if (!attributes.mediumSrc) return {}
          return { "data-medium-src": attributes.mediumSrc }
        },
      },
      largeSrc: {
        default: null,
        parseHTML: (element) => element.getAttribute("data-large-src") || element.getAttribute("data-full-src"),
        renderHTML: (attributes) => {
          if (!attributes.largeSrc) return {}
          return { "data-large-src": attributes.largeSrc }
        },
      },
      display: {
        default: "medium",
        parseHTML: (element) => normalizedDisplay(element.getAttribute("data-display") || "medium"),
        renderHTML: (attributes) => ({ "data-display": normalizedDisplay(attributes.display) }),
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

      const hideToolbar = () => {
        toolbar.style.display = "none"
        altPopover.style.display = "none"
        image.style.outline = "none"
        image.style.outlineOffset = "0"
      }

      const showToolbar = () => {
        wrapper.draggable = false
        wrapper.setAttribute("draggable", "false")
        image.draggable = false
        image.setAttribute("draggable", "false")
        toolbar.style.display = "flex"
        image.style.outline = "2px solid var(--surface-content-color)"
        image.style.outlineOffset = "4px"
        positionToolbar()
      }

      const handleDocumentMouseDown = (event) => {
        const target = event.target
        if (!(target instanceof Node)) return
        if (image.contains(target) || toolbar.contains(target) || altPopover.contains(target)) return

        hideToolbar()
      }

      const preventControlDrag = (event) => {
        event.preventDefault()
      }

      const selectImageNode = (event) => {
        event.preventDefault()

        const pos = getPos()
        if (typeof pos !== "number") return

        editor.chain().focus().setNodeSelection(pos).run()
        showToolbar()
      }

      wrapper.style.cssText = [
        "position:relative",
        "margin:1rem 0",
      ].join(";")
      wrapper.draggable = false
      wrapper.setAttribute("draggable", "false")

      const positionToolbar = () => {
        const wrapperRect = wrapper.getBoundingClientRect()
        const imageRect = image.getBoundingClientRect()
        const toolbarWidth = toolbar.offsetWidth

        if (wrapperRect.width <= 0 || imageRect.width <= 0 || toolbarWidth <= 0) return

        const centerX = imageRect.left - wrapperRect.left + (imageRect.width / 2)
        const minLeft = 0
        const maxLeft = Math.max(0, wrapperRect.width - toolbarWidth)
        const left = Math.min(Math.max(centerX - (toolbarWidth / 2), minLeft), maxLeft)

        toolbar.style.left = `${left}px`
        toolbar.style.transform = "none"
      }

      toolbar.style.cssText = [
        "position:absolute",
        "top:0.75rem",
        "left:0",
        "transform:none",
        "z-index:10",
        "display:none",
        "flex-direction:column",
        "align-items:center",
        "gap:0.4rem",
        "padding:0.55rem",
        "border:1px solid var(--surface-border-color)",
        "border-radius:0.85rem",
        "background:color-mix(in srgb, var(--surface-background-color) 92%, white 8%)",
        "box-shadow:0 12px 32px rgba(15, 23, 42, 0.16)",
      ].join(";")
      toolbar.draggable = false

      altPopover.style.cssText = [
        "display:none",
        "flex-direction:column",
        "align-items:stretch",
        "gap:0.35rem",
        "width:100%",
      ].join(";")
      altPopover.draggable = false
      altInput.type = "text"
      altInput.placeholder = "Describe image"
      altInput.draggable = false
      altInput.style.cssText = [
        "width:100%",
        "min-width:0",
        "border:1px solid var(--surface-border-color)",
        "border-radius:9999px",
        "padding:0.35rem 0.75rem",
        "background:var(--surface-background-color)",
        "color:var(--surface-content-color)",
        "font-size:0.75rem",
      ].join(";")
      altSave.type = "button"
      altSave.textContent = "Save alt text"
      altSave.draggable = false
      altSave.style.cssText = [
        "border:none",
        "border-radius:9999px",
        "padding:0.35rem 0.75rem",
        "background:var(--surface-content-color)",
        "color:var(--surface-background-color)",
        "font-size:0.75rem",
        "cursor:pointer",
        "width:100%",
      ].join(";")
      altPopover.appendChild(altInput)
      altPopover.appendChild(altSave)

      const render = (currentNode) => {
        wrapper.draggable = false
        wrapper.setAttribute("draggable", "false")
        image.draggable = false
        image.setAttribute("draggable", "false")
        image.src = currentNode.attrs.src || ""
        image.alt = currentNode.attrs.alt || ""
        image.title = currentNode.attrs.title || ""
        image.setAttribute("data-attachment-id", currentNode.attrs.attachmentId || "")
        image.setAttribute("data-show-path", currentNode.attrs.showPath || "")
        image.setAttribute("data-original-src", currentNode.attrs.originalSrc || "")
        image.setAttribute("data-small-src", currentNode.attrs.smallSrc || "")
        image.setAttribute("data-medium-src", currentNode.attrs.mediumSrc || "")
        image.setAttribute("data-large-src", currentNode.attrs.largeSrc || "")
        image.setAttribute("data-display", normalizedDisplay(currentNode.attrs.display))
        image.setAttribute("data-align", currentNode.attrs.align || "center")
        image.style.cssText = imageStyle(currentNode.attrs)
        image.className = toolbar.style.display === "none" ? "" : "is-selected"
        altInput.value = currentNode.attrs.alt || ""

        if (toolbar.style.display !== "none") {
          requestAnimationFrame(positionToolbar)
        }

        sizeButtons.forEach((button, value) => applyButtonState(button, normalizedDisplay(currentNode.attrs.display) === value))
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

      ;[
        ["S", "small"],
        ["M", "medium"],
        ["L", "large"],
      ].forEach(([label, value]) => {
        const button = controlButton({
          label,
          isActive: normalizedDisplay(node.attrs.display) === value,
          onMouseDown: () => {
            const pos = getPos()
            const currentNode = typeof pos === "number" ? editor.state.doc.nodeAt(pos) : null
            const attrs = currentNode?.attrs || node.attrs

            updateAttrs({
              display: value,
              src: imageSrcForDisplay(attrs, value),
            })
          },
        })
        sizeButtons.set(value, button)
        sizeRow.appendChild(withTooltip(button, `${value.charAt(0).toUpperCase() + value.slice(1)} image size`))
      })

      ;[
        ["Align left", "left", ALIGN_LEFT_ICON],
        ["Align center", "center", ALIGN_CENTER_ICON],
        ["Align right", "right", ALIGN_RIGHT_ICON],
      ].forEach(([label, value, icon]) => {
        const button = controlButton({
          label,
          icon,
          isActive: node.attrs.align === value,
          onMouseDown: () => updateAttrs({ align: value }),
        })
        alignButtons.set(value, button)
        sizeRow.appendChild(withTooltip(button, label))
      })

      sizeRow.appendChild(withTooltip(controlButton({
        label: "Alt",
        onMouseDown: () => {
          altPopover.style.display = altPopover.style.display === "none" ? "flex" : "none"
          if (altPopover.style.display === "flex") {
            altInput.focus()
            altInput.select()
          }
        },
      }), "Edit alt text"))

      sizeRow.appendChild(withTooltip(controlButton({
        label: "Remove image",
        icon: REMOVE_ICON,
        onMouseDown: removeImage,
      }), "Remove image"))

      toolbar.addEventListener("dragstart", preventControlDrag)
      altPopover.addEventListener("dragstart", preventControlDrag)
      altInput.addEventListener("dragstart", preventControlDrag)
      altSave.addEventListener("dragstart", preventControlDrag)

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
      toolbar.appendChild(altPopover)
      wrapper.appendChild(toolbar)
      wrapper.appendChild(image)

      image.addEventListener("mousedown", selectImageNode)
      document.addEventListener("mousedown", handleDocumentMouseDown, true)

      render(node)

      return {
        dom: wrapper,

        update(updatedNode) {
          if (updatedNode.type.name !== "image") return false
          render(updatedNode)
          return true
        },

        selectNode() {
          showToolbar()
        },

        deselectNode() {
          hideToolbar()
        },

        stopEvent(event) {
          return toolbar.contains(event.target) || altPopover.contains(event.target)
        },

        ignoreMutation() {
          return true
        },

        destroy() {
          toolbar.removeEventListener("dragstart", preventControlDrag)
          altPopover.removeEventListener("dragstart", preventControlDrag)
          altInput.removeEventListener("dragstart", preventControlDrag)
          altSave.removeEventListener("dragstart", preventControlDrag)
          image.removeEventListener("mousedown", selectImageNode)
          document.removeEventListener("mousedown", handleDocumentMouseDown, true)
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
        editor.view.dom.dispatchEvent(new CustomEvent(addonOptions.eventName || "recording-studio-inline-picker", {
          bubbles: true,
          detail: { editor }
        }))
      },
      isDisabled: (editor) => !editor.isEditable
    }
  ]
})