# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@rails/activestorage", to: "activestorage.esm.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from RecordingStudioAttachable::Engine.root.join("app/javascript/controllers/recording_studio_attachable"),
  under: "controllers/recording_studio_attachable",
  to: "controllers/recording_studio_attachable"
pin "recording_studio_attachable/tiptap/attachment_image_addon",
  to: "recording_studio_attachable/tiptap/attachment_image_addon.js"

# Pin FlatPack controllers
pin_all_from FlatPack::Engine.root.join("app/javascript/flat_pack/controllers"), under: "controllers/flat_pack", to: "flat_pack/controllers"
