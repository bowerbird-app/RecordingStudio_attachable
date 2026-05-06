import originalToolbar from "flat_pack/tiptap/original_toolbar"

export default function toolbar(...args) {
  const toolbar = originalToolbar(...args)

  return toolbar.map((item) => {
    if (item !== "attachmentImage") {
      return item
    }

    return {
      name: "attachmentImage",
      dispatch(view) {
        view.dom.dispatchEvent(new CustomEvent("flat-pack:attachment-image-picker", { bubbles: true }))
      }
    }
  })
}