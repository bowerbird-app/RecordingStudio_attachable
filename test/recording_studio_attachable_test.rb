# frozen_string_literal: true

require "test_helper"

class RecordingStudioAttachableTest < Minitest::Test
  def test_version_exists
    refute_nil RecordingStudioAttachable::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, RecordingStudioAttachable::Engine
  end

  def test_upload_view_uses_flatpack_components
    view_path = File.expand_path("../app/views/recording_studio_attachable/attachment_uploads/new.html.erb", __dir__)
    view_source = File.read(view_path)
    upload_controller_source = File.read(
      File.expand_path("../app/javascript/controllers/recording_studio_attachable/upload_controller.js", __dir__)
    )

    assert_includes view_source, "FlatPack::Breadcrumb::Component"
    assert_includes view_source, 'items: [{ text: "Home", href: main_app.root_path, icon: "home" }]'
    assert_includes view_source, "FlatPack::PageTitle::Component"
    assert_includes view_source, "FlatPack::Button::Component"
    assert_includes view_source, "rails_direct_uploads_path"
    assert_includes view_source, "max-files-count-value"
    assert_includes view_source, 'title: "Upload"'
    assert_includes view_source, "Allowed file types:"
    assert_includes view_source, "Drag and drop, or choose"
    assert_includes view_source, 'icon: "upload"'
    assert_includes view_source, 'data: { action: "recording-studio-attachable--upload#browse" }'
    assert_includes view_source, "FlatPack::Modal::Component.new("
    assert_includes view_source, "data-provider-modal-frame"
    assert_includes upload_controller_source, 'credentials: "same-origin"'
    assert_includes upload_controller_source, '"X-CSRF-Token": document.querySelector("meta[name=\'csrf-token\']")?.content || ""'
    assert_includes upload_controller_source, "this.finalizeRequestInFlight = false"
    assert_includes upload_controller_source, "this.maybeFinalize()"
    assert_includes upload_controller_source, "queueSettled()"
    assert_includes upload_controller_source, "async launchProvider(event)"
    assert_includes upload_controller_source, "launchClientPicker(button)"
    assert_includes upload_controller_source, "fetchProviderBootstrap(bootstrapUrl)"
    assert_includes upload_controller_source, "submitProviderImport(importUrl, fileIds)"
    assert_includes upload_controller_source, 'window.addEventListener("message", this.handleProviderMessage)'
    assert_includes upload_controller_source, 'payload.type === "provider-auth-complete"'
    assert_includes upload_controller_source, 'payload.type === "provider-import-complete"'
    refute_includes view_source, '<button type="button" data-action="recording-studio-attachable--upload#browse"'
    refute_includes view_source, 'text: "Attach files"'
    refute_includes view_source, 'text: "Cancel"'
    refute_includes upload_controller_source, "finalizeButton"
    refute_includes view_source, "FlatPack::Card::Component"
    refute_includes view_source, 'title: "Drop files here"'
    refute_includes view_source, "Multiple uploads, previews, and direct-upload progress are handled in-page."
    refute_includes view_source, "Drag files anywhere into this zone or browse from disk."
    refute_includes view_source, "Upload rules"
    refute_includes view_source, 'title: "Queue"'
  end

  def test_image_fallback_controller_toggles_preview_state
    controller_path = File.expand_path("../app/javascript/controllers/recording_studio_attachable/image_fallback_controller.js", __dir__)
    controller_source = File.read(controller_path)

    assert_includes controller_source, 'static targets = ["image", "fallback"]'
    assert_includes controller_source, 'this.imageTarget.classList.add("hidden")'
    assert_includes controller_source, 'this.fallbackTarget.classList.remove("hidden")'
    assert_includes controller_source, 'this.fallbackTarget.classList.add("flex")'
  end

  def test_live_search_controller_debounces_search_form_submission
    controller_path = File.expand_path("../app/javascript/controllers/recording_studio_attachable/live_search_controller.js", __dir__)
    controller_source = File.read(controller_path)

    assert_includes controller_source, "delay: { type: Number, default: 250 }"
    assert_includes controller_source, "if (event.target instanceof HTMLInputElement === false) return"
    assert_includes controller_source, 'if (event.target.type === "hidden") return'
    assert_includes controller_source, "this.element.requestSubmit()"
    assert_includes controller_source, "window.setTimeout(() => {"
    assert_includes controller_source, "window.clearTimeout(this.timeoutId)"
  end

  def test_listing_view_keeps_upload_media_cards_pagination_controls_and_search_ui
    view_path = File.expand_path("../app/views/recording_studio_attachable/recording_attachments/index.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, "FlatPack::Breadcrumb::Component"
    assert_includes view_source, 'items: [{ text: "Home", href: main_app.root_path, icon: "home" }]'
    assert_includes view_source, 'title: "Library"'
    assert_includes view_source, 'text: "Upload"'
    assert_includes view_source, 'icon: "upload"'
    assert_includes view_source, "form_with url: recording_attachments_path(@recording), method: :get"
    assert_includes view_source, 'controller: "recording-studio-attachable--live-search"'
    assert_includes view_source, "input->recording-studio-attachable--live-search#queueSubmit"
    assert_includes view_source, 'turbo_frame: "recording-attachments-results"'
    assert_includes view_source, 'turbo_action: "advance"'
    assert_includes view_source, "hidden_field_tag :scope, @scope"
    assert_includes view_source, "hidden_field_tag :kind, @kind"
    assert_includes view_source, "FlatPack::Search::Component.new("
    assert_includes view_source, 'placeholder: "Search"'
    assert_includes view_source, 'aria: { label: "Search attachments" }'
    refute_includes view_source, 'text: "Apply"'
    refute_includes view_source, 'text: "Clear"'
    assert_includes view_source, 'turbo_frame_tag "recording-attachments-results"'
    assert_includes view_source, 'class="grid grid-cols-2 items-stretch gap-6 lg:grid-cols-5"'
    assert_includes view_source, "card.media padding: :none"
    assert_includes view_source, "card.body do"
    assert_includes view_source, 'class: "h-full w-full object-cover"'
    assert_includes view_source, 'data-controller="recording-studio-attachable--image-fallback"'
    assert_includes view_source, "error->recording-studio-attachable--image-fallback#showFallback"
    assert_includes view_source, 'data-recording-studio-attachable--image-fallback-target="fallback"'
    assert_includes view_source, "Preview unavailable"
    assert_includes view_source, ">IMAGE<"
    assert_includes view_source, 'class="relative aspect-4/3 overflow-hidden bg-(--surface-muted-background-color)"'
    assert_includes view_source, 'File.extname(attachment.original_filename.to_s).delete(".").upcase.presence || "FILE"'
    assert_includes view_source, 'class="aspect-4/3 flex items-center justify-center bg-(--surface-background-color)"'
    assert_includes view_source, 'class="text-xs font-semibold uppercase tracking-[0.18em] text-(--surface-muted-content-color)"'
    assert_includes view_source, "Previous"
    assert_includes view_source, "Next"
    assert_includes view_source, 'data: { turbo_action: "advance" }'
    assert_includes view_source, 'data: { turbo_frame: "_top" }'
    assert_includes view_source, "main_app.rails_blob_path(attachment.file, only_path: true)"
    assert_includes view_source, 'attachment.description.presence || "No description yet"'
    assert_includes view_source, '<h2 class="text-base font-semibold"><%= attachment.name %></h2>'
    assert_includes view_source,
                    '<p class="text-sm text-(--surface-muted-content-color)"><%= attachment.description.presence || "No description yet" %></p>'
    assert_includes view_source, 'title: @query.present? ? "Nothing found" : "Nothing uplaoded yet"'
    assert_includes view_source, 'subtitle: @query.present? ? nil : "Upload files to start building this library."'
    assert_includes view_source, '<circle cx="11" cy="11" r="6" />'
    refute_includes view_source, "No matching attachments"
    refute_includes view_source, "Try another image name."
    assert_includes view_source, "Nothing uplaoded yet"
    refute_includes view_source, "FlatPack::Carousel::Component"
    refute_includes view_source, "variant: :h4"
    refute_includes view_source,
                    "<div class=\"space-y-1\">\n                <h2 class=\"text-base font-semibold\"><%= attachment.name %></h2>"
    refute_includes view_source, 'attachment.image? ? "Preview unavailable" : attachment.original_filename'
    refute_includes view_source, "Scope:"
    refute_includes view_source, "Kind:"
    refute_includes view_source, "Search by attachment name"
    refute_includes view_source, "Bulk remove selected"
    refute_includes view_source, "attachment_ids[]"
    refute_includes view_source, '<div class="grid gap-6 md:grid-cols-2 xl:grid-cols-3">'
    refute_includes view_source, "<% card.body do %>\n                <%= render FlatPack::PageTitle::Component.new("
    refute_match(/FlatPack::Badge::Component\.new\([^\n]+style:\s*:secondary/, view_source)
  end

  def test_attachment_show_view_uses_direct_upload_file_field_and_hides_internal_ids
    view_path = File.expand_path("../app/views/recording_studio_attachable/attachments/show.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, 'file_field_tag "attachment[signed_blob_id]"'
    assert_includes view_source, "main_app.rails_blob_path(@attachment.file, only_path: true)"
    refute_includes view_source, "Recording id"
    refute_includes view_source, "Parent recording id"
  end

  def test_google_drive_addon_files_are_wired_through_the_main_engine
    library_source = File.read(File.expand_path("../lib/recording_studio_attachable.rb", __dir__))
    routes_source = File.read(File.expand_path("../config/routes.rb", __dir__))
    initializer_template = File.read(
      File.expand_path(
        "../lib/generators/recording_studio_attachable/install/templates/recording_studio_attachable_initializer.rb",
        __dir__
      )
    )
    engine_routes_source = File.read(
      File.expand_path("../lib/recording_studio_attachable/google_drive/config/routes.rb", __dir__)
    )
    engine_source = File.read(File.expand_path("../lib/recording_studio_attachable/google_drive/engine.rb", __dir__))
    launcher_source = File.read(
      File.expand_path("../app/javascript/controllers/recording_studio_attachable/google_drive_picker_launcher.js", __dir__)
    )
    view_source = File.read(
      File.expand_path(
        "../lib/recording_studio_attachable/google_drive/app/views/recording_studio_attachable/google_drive/imports/index.html.erb",
        __dir__
      )
    )

    assert_includes library_source, 'require "recording_studio_attachable/google_drive/engine"'
    assert_includes routes_source, 'mount RecordingStudioAttachable::GoogleDrive::Engine, at: "/google_drive", as: :google_drive'
    assert_includes engine_routes_source, 'get "bootstrap", to: "bootstrap#show", as: :bootstrap'
    assert_includes engine_routes_source, 'get "connect", to: "oauth#new", as: :connect'
    assert_includes engine_routes_source, 'delete "connect", to: "oauth#destroy", as: :disconnect'
    assert_includes engine_source, "strategy: :client_picker"
    assert_includes engine_source, 'launcher: "google_drive"'
    assert_includes launcher_source, 'registerUploadProviderLauncher("google_drive"'
    assert_includes launcher_source, "https://apis.google.com/js/api.js"
    assert_includes initializer_template, "strategy: :client_picker"
    assert_includes initializer_template, "GOOGLE_DRIVE_API_KEY"
    assert_includes initializer_template, "GOOGLE_DRIVE_APP_ID"
    assert_includes view_source, 'title: "Google Drive"'
    assert_includes view_source, 'text: "Connect Google Drive"'
    assert_includes view_source, 'text: "Import selected"'
    assert_includes view_source, "google_drive.recording_disconnect_path(@recording)"
    assert_includes view_source, "recording_studio_attachable.recording_attachment_upload_path(@recording, redirect_params)"
    assert_includes view_source, "recording-studio-attachable--provider-modal-frame#openPopup"
    assert_includes view_source, 'hidden_field_tag :embed, "modal" if embedded_upload_provider_request?'
  end
end
