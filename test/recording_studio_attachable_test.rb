# frozen_string_literal: true

require "test_helper"

class RecordingStudioAttachableTest < Minitest::Test
  def test_version_exists
    assert_not_nil RecordingStudioAttachable::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, RecordingStudioAttachable::Engine
  end

  def test_configuration_is_memoized
    first = RecordingStudioAttachable.configuration
    second = RecordingStudioAttachable.configuration

    assert_same first, second
  end

  def test_register_upload_provider_delegates_to_configuration
    original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    configuration = Object.new
    captured = nil
    configuration.define_singleton_method(:register_upload_provider) do |*args, **kwargs|
      captured = [args, kwargs]
      :provider
    end
    RecordingStudioAttachable.instance_variable_set(:@configuration, configuration)

    result = RecordingStudioAttachable.register_upload_provider(:google_drive, label: "Google Drive")

    assert_equal :provider, result
    assert_equal [[:google_drive], { label: "Google Drive" }], captured
  ensure
    RecordingStudioAttachable.instance_variable_set(:@configuration, original_configuration)
  end

  def test_configure_without_a_block_leaves_configuration_unchanged
    configuration = RecordingStudioAttachable.configuration

    assert_nil RecordingStudioAttachable.configure
    assert_same configuration, RecordingStudioAttachable.configuration
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
    assert_includes view_source, "image-processing-enabled-value"
    assert_includes view_source, "image-processing-max-width-value"
    assert_includes view_source, "image-processing-max-height-value"
    assert_includes view_source, "image-processing-quality-value"
    assert_includes view_source, "remove-button-template-value"
    assert_includes view_source, 'text: "X"'
    assert_includes view_source, "style: :ghost"
    assert_includes view_source, "size: :md"
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
    assert_includes upload_controller_source, 'import { preprocessImageFile, shouldPreprocessImageFile } from "controllers/recording_studio_attachable/image_preprocessing"'
    assert_includes upload_controller_source, 'entry.status = "processing"'
    assert_includes upload_controller_source, "await this.preprocessEntryFile(entry)"
    assert_includes upload_controller_source, "const validationError = this.validationError(entry.file)"
    assert_includes upload_controller_source, "initialStatusFor(file)"
    assert_includes upload_controller_source, "deferSizeValidationUntilAfterProcessing(file)"
    assert_includes upload_controller_source, "shouldPreprocessImageFile(file, this.imageProcessingOptions())"
    assert_includes upload_controller_source, "maxBytes: this.maxFileSizeValue"
    assert_includes upload_controller_source, "Optimizing image before upload…"
    assert_includes upload_controller_source, "removeButtonTemplate: String"
    assert_includes upload_controller_source, "const remove = this.removeButtonTemplateValue"
    assert_includes upload_controller_source, 'data-entry-content class="flex items-start gap-4"'
    assert_includes upload_controller_source, "currentContent.replaceWith(nextContent)"
    assert_includes upload_controller_source, 'window.addEventListener("message", this.handleProviderMessage)'
    assert_includes upload_controller_source, 'window.addEventListener("storage", this.handleProviderStorage)'
    assert_includes upload_controller_source, 'payload.type === "provider-auth-complete"'
    assert_includes upload_controller_source, 'payload.type === "provider-import-complete"'
    assert_includes upload_controller_source, 'event.key !== PROVIDER_EVENT_STORAGE_KEY'
    assert_not_includes upload_controller_source, "node.outerHTML = this.entryTemplate(entry)"
    assert_not_includes view_source, '<button type="button" data-action="recording-studio-attachable--upload#browse"'
    assert_not_includes view_source, 'text: "Attach files"'
    assert_not_includes view_source, 'text: "Cancel"'
    assert_not_includes upload_controller_source, "finalizeButton"
    assert_not_includes view_source, "FlatPack::Card::Component"
    assert_not_includes view_source, 'title: "Drop files here"'
    assert_not_includes view_source, "Multiple uploads, previews, and direct-upload progress are handled in-page."
    assert_not_includes view_source, "Drag files anywhere into this zone or browse from disk."
    assert_not_includes view_source, "Upload rules"
    assert_not_includes view_source, 'title: "Queue"'
  end

  def test_attachment_show_view_uses_flatpack_breadcrumb_above_title
    view_path = File.expand_path("../app/views/recording_studio_attachable/attachments/show.html.erb", __dir__)
    view_source = File.read(view_path)
    controller_path = File.expand_path("../app/controllers/recording_studio_attachable/application_controller.rb", __dir__)
    controller_source = File.read(controller_path)
    model_path = File.expand_path("../app/models/recording_studio_attachable/attachment.rb", __dir__)
    model_source = File.read(model_path)
    configuration_path = File.expand_path("../lib/recording_studio_attachable/configuration.rb", __dir__)
    configuration_source = File.read(configuration_path)

    assert_includes view_source, "FlatPack::Breadcrumb::Component"
    assert_includes view_source, 'back_text: "Back"'
    assert_includes view_source, 'back_icon: "arrow-left"'
    assert_includes view_source, "back_href: request.referer.presence || main_app.root_path"
    assert_includes view_source, 'items: [{ text: "Home", href: main_app.root_path, icon: "home" }]'
    assert_match(/FlatPack::Breadcrumb::Component.*FlatPack::PageTitle::Component/m, view_source)
    assert_includes configuration_source, "DEFAULT_IMAGE_VARIANTS = {"
    assert_includes configuration_source, "square_small: { resize_to_fill: [128, 128] }"
    assert_includes configuration_source, "square_med: { resize_to_fill: [400, 400] }"
    assert_includes configuration_source, "square_large: { resize_to_fill: [800, 800] }"
    assert_includes configuration_source, "small: { resize_to_limit: [480, 480] }"
    assert_includes configuration_source, "med: { resize_to_limit: [960, 960] }"
    assert_includes configuration_source, "large: { resize_to_limit: [1600, 1600] }"
    assert_includes configuration_source, "xlarge: { resize_to_limit: [2400, 2400] }"
    assert_includes model_source, "def variant_named(name)"
    assert_includes model_source, "def preview_target_named(name)"
    assert_includes model_source, "RecordingStudioAttachable.configuration.image_variant(name)"
    assert_includes model_source, "return variant_named(name) if file.variable?"
    assert_includes controller_source, "helper_method :authorized_attachment_preview_path"
    assert_includes controller_source, "def authorized_attachment_preview_path(recording, variant_name)"
    assert_includes controller_source, "attachment_preview_file_path(recording, variant_name: variant_name)"
    assert_includes controller_source, "helper_method :authorized_attachment_file_path"
    assert_includes view_source, "preview_path = authorized_attachment_preview_path(@attachment_recording, :large)"
    assert_includes view_source, "image_tag preview_path"
    assert_not_includes view_source, "overflow-hidden rounded-lg border border-[var(--surface-border-color)] bg-[var(--surface-muted-background-color)]"
    assert_not_includes view_source, "FlatPack::Badge::Component"
    assert_not_includes view_source, 'title: "Attachment details"'
    assert_not_includes view_source, 'title: "Revise attachment"'
    assert_not_includes view_source, 'text: "Download"'
    assert_not_includes view_source, 'text: "Save revision"'
  end

  def test_image_fallback_controller_toggles_preview_state
    controller_path = File.expand_path("../app/javascript/controllers/recording_studio_attachable/image_fallback_controller.js", __dir__)
    controller_source = File.read(controller_path)

    assert_includes controller_source, 'static targets = ["image", "fallback"]'
    assert_includes controller_source, 'this.imageTarget.classList.add("hidden")'
    assert_includes controller_source, 'this.fallbackTarget.classList.remove("hidden")'
    assert_includes controller_source, 'this.fallbackTarget.classList.add("flex")'
  end

  def test_image_preprocessing_utility_only_resizes_supported_raster_types
    utility_path = File.expand_path("../app/javascript/controllers/recording_studio_attachable/image_preprocessing.js", __dir__)
    utility_source = File.read(utility_path)

    assert_includes utility_source, 'const PROCESSABLE_CONTENT_TYPES = ["image/jpeg", "image/png", "image/webp"]'
    assert_includes utility_source, "export function shouldPreprocessImageFile(file, options = {}) {"
    assert_includes utility_source, "maxBytes: positiveInteger(options.maxBytes)"
    assert_includes utility_source, "const shouldOptimizeForSize = normalizedOptions.maxBytes && file.size > normalizedOptions.maxBytes"
    assert_includes utility_source, "return bestBlob"
    assert_includes utility_source, "canvas.toBlob(resolve, contentType, encoderQuality)"
    assert_includes utility_source, "new File([processedBlob], file.name"
    assert_not_includes utility_source, '"image/gif"'
    assert_not_includes utility_source, '"image/svg+xml"'
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
    grid_partial_source = File.read(
      File.expand_path("../app/views/recording_studio_attachable/recording_attachments/_grid.html.erb", __dir__)
    )
    list_partial_source = File.read(
      File.expand_path("../app/views/recording_studio_attachable/recording_attachments/_list.html.erb", __dir__)
    )

    assert_includes view_source, "FlatPack::Breadcrumb::Component"
    assert_includes view_source, 'items: [{ text: "Home", href: main_app.root_path, icon: "home" }]'
    assert_includes view_source, 'title: "Library"'
    assert_includes view_source, 'text: "Upload"'
    assert_includes view_source, 'icon: "upload"'
    assert_includes view_source, 'link_to recording_attachment_upload_path(@recording), class: "inline-flex", data: { turbo_frame: "_top" }'
    assert_includes view_source, 'icon: "squares-2x2"'
    assert_includes view_source, 'icon: "list-bullet"'
    assert_includes view_source, "icon_only: true"
    assert_includes view_source, "size: :md"
    assert_includes view_source, 'aria: { label: "Grid view" }'
    assert_includes view_source, 'aria: { label: "List view" }'
    assert_not_includes view_source, ">View<"
    assert_not_includes view_source, 'text: "Grid"'
    assert_not_includes view_source, 'text: "List"'
    assert_includes view_source, "form_with url: recording_attachments_path(@recording), method: :get"
    assert_includes view_source, 'controller: "recording-studio-attachable--live-search"'
    assert_includes view_source, "input->recording-studio-attachable--live-search#queueSubmit"
    assert_includes view_source, 'turbo_frame: "recording-attachments-results"'
    assert_includes view_source, 'turbo_action: "advance"'
    assert_includes view_source, "hidden_field_tag :scope, @scope"
    assert_includes view_source, "hidden_field_tag :kind, @kind"
    assert_includes view_source, "hidden_field_tag :view, @view_mode"
    assert_includes view_source, "FlatPack::Search::Component.new("
    assert_includes view_source, 'placeholder: "Search"'
    assert_includes view_source, 'aria: { label: "Search attachments" }'
    assert_not_includes view_source, 'text: "Apply"'
    assert_not_includes view_source, 'text: "Clear"'
    assert_includes view_source, 'turbo_frame_tag "recording-attachments-results"'
    assert_includes view_source, 'render "grid", attachments: @attachments'
    assert_includes view_source, 'render "list", attachments: @attachments'
    assert_includes view_source, "Previous"
    assert_includes view_source, "Next"
    assert_includes view_source, 'data: { turbo_frame: "recording-attachments-results", turbo_action: "advance" }'
    assert_includes view_source, "@view_mode == :grid ? :secondary : :ghost"
    assert_includes view_source, "@view_mode == :list ? :secondary : :ghost"
    assert_includes view_source, 'title: @query.present? ? "Nothing found" : "Nothing uplaoded yet"'
    assert_includes view_source, 'subtitle: @query.present? ? nil : "Upload files to start building this library."'
    assert_includes view_source, '<circle cx="11" cy="11" r="6" />'
    assert_includes grid_partial_source, 'class="grid grid-cols-2 items-stretch gap-6 lg:grid-cols-5"'
    assert_includes grid_partial_source, "card.media padding: :none"
    assert_not_includes grid_partial_source, "card.body do"
    assert_includes grid_partial_source, 'class: "h-full w-full object-cover"'
    assert_includes grid_partial_source, 'data-controller="recording-studio-attachable--image-fallback"'
    assert_includes grid_partial_source, "error->recording-studio-attachable--image-fallback#showFallback"
    assert_includes grid_partial_source, 'data-recording-studio-attachable--image-fallback-target="fallback"'
    assert_includes grid_partial_source, "Preview unavailable"
    assert_includes grid_partial_source, ">IMAGE<"
    assert_includes grid_partial_source, 'class="relative aspect-4/3 overflow-hidden bg-(--surface-muted-background-color)"'
    assert_includes grid_partial_source, 'File.extname(attachment.original_filename.to_s).delete(".").upcase.presence || "FILE"'
    assert_includes grid_partial_source, 'class="aspect-4/3 flex items-center justify-center bg-(--surface-background-color)"'
    assert_includes grid_partial_source, 'class="text-xs font-semibold uppercase tracking-[0.18em] text-(--surface-muted-content-color)"'
    assert_includes grid_partial_source, "preview_path = authorized_attachment_preview_path(attachment_recording, :med)"
    assert_includes grid_partial_source, "image_tag preview_path"
    assert_not_includes grid_partial_source, '<h2 class="text-base font-semibold"><%= attachment.name %></h2>'
    assert_includes list_partial_source, ">Preview<"
    assert_not_includes list_partial_source, ">Kind<"
    assert_not_includes list_partial_source, ">Type<"
    assert_not_includes list_partial_source, ">Size<"
    assert_includes list_partial_source, 'number_to_human_size(attachment.byte_size, strip_insignificant_zeros: true).downcase.delete(" ")'
    assert_includes list_partial_source, "<%= display_content_type %> <%= display_size %>"
    assert_includes list_partial_source, 'data: { turbo_frame: "_top" }'
    assert_operator list_partial_source.scan("attachment_path(attachment_recording)").length, :>=, 2
    assert_includes list_partial_source, "preview_path = authorized_attachment_preview_path(attachment_recording, :square_small)"
    assert_includes list_partial_source, "image_tag preview_path"
    assert_includes list_partial_source, 'FlatPack::Tooltip::Component.new(text: "Download")'
    assert_includes list_partial_source, 'icon: "arrow-down-tray", icon_only: true'
    assert_includes list_partial_source, 'aria: { label: "Download attachment" }'
    assert_includes list_partial_source, 'FlatPack::Tooltip::Component.new(text: "Trash")'
    assert_includes list_partial_source, "destroy_attachment_path(attachment_recording)"
    assert_includes list_partial_source, 'icon: "trash", icon_only: true'
    assert_includes list_partial_source, 'aria: { label: "Trash attachment" }'
    assert_not_includes list_partial_source, 'text: "View"'
    assert_not_includes list_partial_source, "<%= attachment.original_filename %>"
    assert_not_includes view_source, "No matching attachments"
    assert_not_includes view_source, "Try another image name."
    assert_includes view_source, "Nothing uplaoded yet"
    assert_not_includes view_source, "FlatPack::Carousel::Component"
    assert_not_includes view_source, "variant: :h4"
    assert_not_includes view_source,
                        "<div class=\"space-y-1\">\n                <h2 class=\"text-base font-semibold\"><%= attachment.name %></h2>"
    assert_not_includes view_source, 'attachment.description.presence || "No description yet"'
    assert_not_includes view_source, "No description yet"
    assert_not_includes view_source, 'attachment.image? ? "Preview unavailable" : attachment.original_filename'
    assert_not_includes view_source, "Scope:"
    assert_not_includes view_source, "Kind:"
    assert_not_includes view_source, "Search by attachment name"
    assert_not_includes view_source, "Bulk remove selected"
    assert_not_includes view_source, "attachment_ids[]"
    assert_not_includes view_source, '<div class="grid gap-6 md:grid-cols-2 xl:grid-cols-3">'
    assert_not_includes view_source, "<% card.body do %>\n                <%= render FlatPack::PageTitle::Component.new("
    assert_no_match(/FlatPack::Badge::Component\.new\([^\n]+style:\s*:secondary/, view_source)
  end

  def test_attachment_show_view_hides_edit_controls_and_internal_ids
    view_path = File.expand_path("../app/views/recording_studio_attachable/attachments/show.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, "preview_path = authorized_attachment_preview_path(@attachment_recording, :large)"
    assert_includes view_source, "image_tag preview_path"
    assert_not_includes view_source, "FlatPack::Badge::Component"
    assert_not_includes view_source, 'controller: "recording-studio-attachable--attachment-revision-upload"'
    assert_not_includes view_source, 'hidden_field_tag "attachment[signed_blob_id]"'
    assert_not_includes view_source, 'file_field_tag "attachment[file]"'
    assert_not_includes view_source, 'text: "Download"'
    assert_not_includes view_source, 'text: "Save revision"'
    assert_not_includes view_source, "Recording id"
    assert_not_includes view_source, "Parent recording id"
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
