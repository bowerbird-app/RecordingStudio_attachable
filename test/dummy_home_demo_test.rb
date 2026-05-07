# frozen_string_literal: true

require "test_helper"

class DummyHomeDemoTest < Minitest::Test
  def test_dummy_home_page_has_root_and_page_demo_actions
    home_view = File.read(File.expand_path("dummy/app/views/home/index.html.erb", __dir__))

    assert_includes home_view, 'title: "Attachment demo"'
    assert_includes home_view, 'subtitle: "Workspace uploads accept images and files. Page uploads accept images only."'
    assert_operator home_view.scan("FlatPack::Card::Component.new(style: :default)").length, :>=, 2
    assert_operator home_view.scan("<% card.body do %>").length, :>=, 2
    assert_includes home_view, 'title: "Workspace"'
    assert_includes home_view, 'subtitle: "Upload images, PDFs, and text files to the workspace library."'
    assert_includes home_view, 'title: "Workspace",'
    assert_includes home_view, "anchor_link: true"
    assert_includes home_view, 'text: "Library"'
    assert_includes home_view, 'title: "Page"'
    assert_includes home_view, 'subtitle: "Add images below page recording"'
    assert_includes home_view, 'text: "Page library"'
    assert_includes home_view, 'text: "View"'
    assert_includes home_view, 'text: "Edit inline"'
  end

  def test_dummy_sign_in_view_keeps_title_in_card_body_without_header
    sign_in_view = File.read(File.expand_path("dummy/app/views/devise/sessions/new.html.erb", __dir__))

    assert_includes sign_in_view, "FlatPack::PageTitle::Component.new("
    assert_includes sign_in_view, 'title: "Sign In"'
    assert_includes sign_in_view, 'class: "mb-6"'
    assert_includes sign_in_view, "<% card.body do %>"
    refute_includes sign_in_view, "<% card.header do %>"
  end

  def test_dummy_home_controller_builds_root_and_page_attachment_paths
    home_controller = File.read(File.expand_path("dummy/app/controllers/home_controller.rb", __dir__))

    assert_includes home_controller, "@page = Page.first"
    assert_includes home_controller, "@page_show_path = page_path(@page) if @page.present?"
    assert_includes home_controller, "@page_edit_path = edit_page_path(@page) if @page.present?"
    assert_includes home_controller, "@page_recording = RecordingStudio::Recording.unscoped.find_by("
    assert_includes home_controller, "@root_attachment_listing_path = attachment_listing_path(@root_recording, scope: :subtree, kind: :all)"
    assert_includes home_controller, "@page_attachment_upload_path = page_attachment_upload_path"
    assert_includes home_controller, "recording_studio_attachable.recording_attachment_upload_path("
    assert_includes home_controller, 'redirect_mode: "return_to"'
    assert_includes home_controller, "return_to: @page_show_path"
  end

  def test_dummy_page_recordable_is_registered_seeded_and_migrated
    page_model = File.read(File.expand_path("dummy/app/models/page.rb", __dir__))
    workspace_model = File.read(File.expand_path("dummy/app/models/workspace.rb", __dir__))
    recording_studio_initializer = File.read(File.expand_path("dummy/config/initializers/recording_studio.rb", __dir__))
    seeds = File.read(File.expand_path("dummy/db/seeds.rb", __dir__))
    schema = File.read(File.expand_path("dummy/db/schema.rb", __dir__))

    assert_includes page_model, "class Page < ApplicationRecord"
    assert_includes page_model, "RecordingStudio::Capabilities::Attachable"
    assert_includes page_model, 'allowed_content_types: [ "image/*" ]'
    assert_includes page_model, "enabled_attachment_kinds: %i[ image ]"
    assert_includes page_model, "before_destroy :raise_page_destroy_immutable_error"
    assert_includes page_model, "def readonly?"
    assert_includes page_model, "def raise_immutable_error; end"
    assert_includes page_model, "def raise_page_destroy_immutable_error"
    assert_includes workspace_model, 'allowed_content_types: [ "image/*", "application/pdf", "text/plain" ]'
    assert_includes workspace_model, "enabled_attachment_kinds: %i[ image file ]"
    assert_includes recording_studio_initializer, '"Workspace", "Page", "RecordingStudioAttachable::Attachment"'
    assert_includes seeds, "user = User.find_or_initialize_by(email: admin_email)"
    assert_includes seeds, "unless user.persisted? && user.valid_password?(admin_password)"
    assert_includes seeds, 'page = Page.find_or_create_by!(title: "Home page")'
    assert_includes seeds, "recordable: page"
    assert_includes schema, 'create_table "pages"'
    assert_includes schema, 't.text "body"'
    assert_includes schema, 'create_table "recording_studio_attachable_attachments"'
    assert_includes schema, 't.string "title"'
    assert_includes page_model, "validates :title, presence: true"
  end

  def test_dummy_page_routes_controller_and_views_support_show_and_rich_text_editing
    routes = File.read(File.expand_path("dummy/config/routes.rb", __dir__))
    controller = File.read(File.expand_path("dummy/app/controllers/pages_controller.rb", __dir__))
    show_view = File.read(File.expand_path("dummy/app/views/pages/show.html.erb", __dir__))
    view = File.read(File.expand_path("dummy/app/views/pages/edit.html.erb", __dir__))
    picker_controller = File.read(File.expand_path("../app/javascript/controllers/recording_studio_attachable/attachment_image_picker_controller.js", __dir__))
    html_preview_controller = File.read(File.expand_path("dummy/app/javascript/controllers/page_html_preview_controller.js", __dir__))
    importmap = File.read(File.expand_path("dummy/config/importmap.rb", __dir__))
    addon = File.read(File.expand_path("../app/javascript/recording_studio_attachable/tiptap/attachment_image_addon.js", __dir__))
    html_preview_addon = File.read(File.expand_path("dummy/app/javascript/page_html_preview_addon.js", __dir__))

    assert_includes routes, "resources :pages, only: %i[show edit update]"
    assert_includes controller, "class PagesController < ApplicationController"
    assert_includes controller, "@page = Page.find(params[:id])"
    assert_includes controller, "def show; end"
    assert_includes controller, "@page_recording = RecordingStudio::Recording.unscoped.find_by(recordable: @page)"
    assert_includes controller,
                    "@page_attachment_picker_path = recording_studio_attachable.recording_attachment_picker_path(@page_recording)"
    assert_includes controller, "@page_attachment_create_path = recording_studio_attachable.recording_attachments_path("
    assert_includes controller, 'redirect_mode: "return_to"'
    assert_includes controller, "return_to: page_path(@page)"
    assert_includes show_view, "FlatPack::Breadcrumb::Component.new("
    assert_includes show_view, 'items: [{ text: "Home", href: root_path, icon: "home" }]'
    assert_includes show_view, "title: @page.title"
    assert_includes show_view, 'subtitle: "Review the inline page content and related page actions."'
    assert_includes show_view, 'class="page-inline-content prose max-w-none text-(--surface-content-color)"'
    assert_includes show_view, "<%= sanitize("
    assert_includes show_view, '@page.body.presence || "<p>No page content yet.</p>"'
    assert_includes show_view, "attributes: %w[href src alt title data-display data-align]"
    assert_includes show_view, '.page-inline-content img[data-display="small"] {'
    assert_includes show_view, '.page-inline-content img[data-align="right"] {'
    assert_includes show_view, 'text: "Edit inline"'
    refute_includes show_view, 'text: "Back to home"'
    refute_includes show_view, "FlatPack::Card::Component.new(style: :default)"
    assert_includes controller, 'redirect_to edit_page_path(@page), notice: "Page updated."'
    assert_includes importmap, 'pin "page_html_preview_addon"'
    assert_includes importmap, 'pin "recording_studio_attachable/tiptap/attachment_image_addon"'
    assert_includes view, "FlatPack::PageTitle::Component.new("
    assert_includes view, "FlatPack::Breadcrumb::Component.new("
    assert_includes view, "show_back: true"
    assert_includes view, 'back_text: "Back"'
    assert_includes view, 'back_icon: "arrow-left"'
    assert_includes view, 'items: [{ text: "Home", href: root_path, icon: "home" }]'
    assert_includes view, 'title: "Edit inline"'
    assert_includes view, 'subtitle: "Update page copy and formatted content for the inline recording demo."'
    assert_includes view, '<%= link_to page_path(@page), class: "inline-flex" do %>'
    assert_includes view, 'text: "View"'
    assert_includes view, "FlatPack::TextInput::Component.new("
    assert_includes view, 'name: "page[title]"'
    assert_includes view, "FlatPack::TextArea::Component.new("
    assert_includes view, 'name: "page[body]"'
    assert_includes view, "rich_text: true"
    assert_includes view, "addons: [{ name: :attachment_image }, { name: :html_preview }]"
    assert_includes view, '"attachmentImage"'
    assert_includes view, '"htmlPreview"'
    assert_includes view, 'data-controller="page-html-preview"'
    assert_includes view, 'data-action="flat-pack:html-preview->page-html-preview#openFromToolbar"'
    assert_includes view, 'title: "HTML output"'
    assert_includes view, 'data-page-html-preview-target="output"'
    assert_includes view, 'data-action="recording-studio-inline-picker->recording-studio-attachable--attachment-image-picker#openPickerFromToolbar"'
    assert_includes view, "bubble_menu: false"
    assert_includes view, "floating_menu: false"
    assert_includes view, 'data-controller="recording-studio-attachable--attachment-image-picker"'
    assert_includes view, "data-recording-studio-attachable--attachment-image-picker-image-processing-enabled-value="
    assert_includes view, "data-recording-studio-attachable--attachment-image-picker-image-processing-max-width-value="
    assert_includes view, "data-recording-studio-attachable--attachment-image-picker-image-processing-max-height-value="
    assert_includes view, "data-recording-studio-attachable--attachment-image-picker-image-processing-quality-value="
    assert_includes view, 'title: "Insert image"'
    assert_includes view, 'text: "Upload"'
    assert_includes view, 'icon: "upload"'
    assert_includes view, 'class="flex h-full min-h-0 flex-col gap-4"'
    assert_includes view, 'class="w-full lg:w-auto"'
    assert_includes view, "FlatPack::Search::Component.new("
    assert_includes view, 'placeholder: "Search"'
    assert_includes view, 'class="min-h-0 flex-1 overflow-y-auto pr-1"'
    assert_includes view, 'data-recording-studio-attachable--attachment-image-picker-target="gallery"'
    assert_includes view, 'data-recording-studio-attachable--attachment-image-picker-target="fileInput"'
    assert_includes view, "data-recording-studio-attachable--attachment-image-picker-max-file-size-value="
    refute_includes view, 'class="-mb-4 flex h-[calc(100%+1rem)] min-h-0 flex-col gap-4"'
    refute_includes view, 'class="max-h-96 overflow-y-auto pr-1"'
    refute_includes view, 'text: "Close"'
    assert_includes view, 'text: "Save page"'
    assert_includes picker_controller, "application.getControllerForElementAndIdentifier"
    assert_includes picker_controller, "openPickerFromToolbar(event)"
    assert_includes picker_controller, "async loadAttachments({ append = false, reset = false } = {}) {"
    assert_includes picker_controller, "createAttachmentFromBlob(file, blob)"
    assert_includes picker_controller, 'import { preprocessImageFile } from "controllers/recording_studio_attachable/image_preprocessing"'
    assert_includes picker_controller, "const processed = await preprocessImageFile(file, this.imageProcessingOptions())"
    assert_includes picker_controller, "maxBytes: this.maxFileSizeValue"
    assert_includes picker_controller, "new DirectUpload(uploadFile, this.directUploadUrlValue)"
    assert_includes picker_controller, 'button.setAttribute("aria-label", attachment.name || "Untitled image")'
    assert_includes picker_controller, "attachmentId: attachment.id"
    assert_includes picker_controller, "showPath: attachment.show_path"
    assert_includes picker_controller, 'display: "medium"'
    assert_includes picker_controller, 'align: "center"'
    refute_includes picker_controller, 'const body = document.createElement("div")'
    assert_includes addon, 'registerTiptapAddon("attachment_image"'
    assert_includes addon, "const ManagedAttachmentImage = Image.extend({"
    assert_includes addon, "data-attachment-id"
    assert_includes addon, "updateAttachmentImageAttrs"
    assert_includes addon, "removeSelectedAttachmentImage"
    assert_includes addon, 'label: "Remove"'
    assert_includes addon, 'label: "Alt"'
    assert_includes addon, 'name: "attachmentImage"'
    assert_includes addon, "recording-studio-inline-picker"
    assert_includes html_preview_addon, 'registerTiptapAddon("html_preview"'
    assert_includes html_preview_addon, 'name: "htmlPreview"'
    assert_includes html_preview_addon, 'label: addonOptions.label || "View HTML"'
    assert_includes html_preview_addon, "flat-pack:html-preview"
    assert_includes html_preview_controller, "openFromToolbar(event)"
    assert_includes html_preview_controller, "this.outputTarget.value = editor.getHTML()"
    assert_includes html_preview_controller, "application.getControllerForElementAndIdentifier"
    refute_includes view, "FlatPack::Card::Component.new(style: :default)"
    refute_includes view, 'text: "Back to demo"'
  end

  def test_attachment_listing_uses_card_grid_with_empty_state_when_no_results_exist
    listing_view = File.read(File.expand_path("../app/views/recording_studio_attachable/recording_attachments/index.html.erb", __dir__))
    grid_partial = File.read(
      File.expand_path("../app/views/recording_studio_attachable/recording_attachments/_grid.html.erb", __dir__)
    )
    list_partial = File.read(
      File.expand_path("../app/views/recording_studio_attachable/recording_attachments/_list.html.erb", __dir__)
    )

    assert_includes listing_view, "FlatPack::Breadcrumb::Component"
    assert_includes listing_view, 'items: [{ text: "Home", href: main_app.root_path, icon: "home" }]'
    assert_includes listing_view, 'title: "Library"'
    assert_includes listing_view, "parent_recordable.respond_to?(:title) && parent_recordable.title.present?"
    assert_includes listing_view, "subtitle: parent_recordable_name"
    assert_includes listing_view, "view: @view_mode"
    assert_includes listing_view, 'text: "Upload"'
    assert_includes listing_view, 'icon: "upload"'
    assert_includes listing_view, 'icon: "squares-2x2"'
    assert_includes listing_view, 'icon: "list-bullet"'
    assert_includes listing_view, "icon_only: true"
    assert_includes listing_view, "size: :md"
    refute_includes listing_view, ">View<"
    refute_includes listing_view, 'text: "Grid"'
    refute_includes listing_view, 'text: "List"'
    assert_includes listing_view, "form_with url: recording_attachments_path(@recording), method: :get"
    assert_includes listing_view, 'controller: "recording-studio-attachable--live-search"'
    assert_includes listing_view, "input->recording-studio-attachable--live-search#queueSubmit"
    assert_includes listing_view, 'turbo_frame: "recording-attachments-results"'
    assert_includes listing_view, 'turbo_action: "advance"'
    assert_includes listing_view, "hidden_field_tag :view, @view_mode"
    assert_includes listing_view, "FlatPack::Search::Component.new("
    assert_includes listing_view, 'placeholder: "Search"'
    refute_includes listing_view, 'text: "Apply"'
    refute_includes listing_view, 'text: "Clear"'
    assert_includes listing_view, 'turbo_frame_tag "recording-attachments-results"'
    assert_includes listing_view, 'render "grid", attachments: @attachments'
    assert_includes listing_view, 'render "list", attachments: @attachments'
    assert_includes listing_view, 'data: { turbo_frame: "recording-attachments-results", turbo_action: "advance" }'
    assert_includes listing_view, "@view_mode == :grid ? :secondary : :ghost"
    assert_includes listing_view, "@view_mode == :list ? :secondary : :ghost"
    assert_includes listing_view, 'title: @query.present? ? "Nothing found" : "Nothing uplaoded yet"'
    assert_includes listing_view, 'subtitle: @query.present? ? nil : "Upload files to start building this library."'
    assert_includes listing_view, '<circle cx="11" cy="11" r="6" />'
    assert_includes grid_partial, 'class="grid grid-cols-2 items-stretch gap-6 lg:grid-cols-5"'
    assert_includes grid_partial, "card.media padding: :none"
    assert_includes grid_partial, 'data-controller="recording-studio-attachable--image-fallback"'
    assert_includes grid_partial, "preview_path = attachment_preview_path(attachment, :med)"
    assert_includes grid_partial, "image_tag preview_path"
    assert_includes grid_partial, "main_app.rails_blob_path(attachment.file, only_path: true)"
    assert_includes list_partial, 'number_to_human_size(attachment.byte_size, strip_insignificant_zeros: true).downcase.delete(" ")'
    assert_includes list_partial, "<%= display_content_type %> <%= display_size %>"
    assert_includes list_partial, 'data: { turbo_frame: "_top" }'
    assert_operator list_partial.scan("attachment_path(attachment_recording)").length, :>=, 2
    assert_includes list_partial, 'FlatPack::Tooltip::Component.new(text: "Download")'
    assert_includes list_partial, 'icon: "arrow-down-tray", icon_only: true'
    assert_includes list_partial, 'FlatPack::Tooltip::Component.new(text: "Trash")'
    assert_includes list_partial, "destroy_attachment_path(attachment_recording)"
    assert_includes list_partial, 'icon: "trash", icon_only: true'
    refute_includes list_partial, 'text: "View"'
    refute_includes list_partial, ">Type<"
    refute_includes list_partial, ">Size<"
    refute_includes list_partial, "<%= attachment.original_filename %>"
    refute_includes listing_view, "No matching attachments"
    refute_includes listing_view, "Try another image name."
    assert_includes listing_view, "Nothing uplaoded yet"
    refute_includes listing_view, "FlatPack::Carousel::Component"
    refute_includes listing_view, "variant: :h4"
    refute_includes grid_partial, "card.body do"
    refute_includes grid_partial, '<h2 class="text-base font-semibold"><%= attachment.name %></h2>'
    refute_includes listing_view,
                    "<div class=\"space-y-1\">\n                <h2 class=\"text-base font-semibold\"><%= attachment.name %></h2>"
    refute_includes listing_view, 'attachment.description.presence || "No description yet"'
    refute_includes listing_view, "No description yet"
    refute_includes listing_view, 'attachment.image? ? "Preview unavailable" : attachment.original_filename'
    refute_includes listing_view, "Bulk remove selected"
    refute_includes listing_view, "attachment_ids[]"
    refute_includes listing_view, '<div class="grid gap-6 md:grid-cols-2 xl:grid-cols-3">'
    refute_includes listing_view, "<% card.body do %>\n                <%= render FlatPack::PageTitle::Component.new("
  end

  def test_dummy_layouts_reference_propshaft_resolvable_css_assets
    application_layout = File.read(File.expand_path("dummy/app/views/layouts/application.html.erb", __dir__))
    sidebar_layout = File.read(File.expand_path("dummy/app/views/layouts/flat_pack_sidebar.html.erb", __dir__))
    blank_layout = File.read(File.expand_path("../app/views/layouts/recording_studio_attachable/blank.html.erb", __dir__))

    [application_layout, sidebar_layout, blank_layout].each do |layout|
      assert_includes layout, 'stylesheet_link_tag "application.css"'
      assert_includes layout, 'stylesheet_link_tag "flat_pack/variables"'
      assert_includes layout, 'stylesheet_link_tag "flat_pack/rich_text"'
      assert_includes layout, 'stylesheet_link_tag "tailwind.css"'
    end

    assert_includes blank_layout, "style: :danger"
    refute_includes blank_layout, "style: :error"
  end

  def test_dummy_javascript_boot_enables_turbo_drive_and_active_storage
    importmap = File.read(File.expand_path("dummy/config/importmap.rb", __dir__))
    application_js = File.read(File.expand_path("dummy/app/javascript/application.js", __dir__))

    assert_includes importmap, 'pin "@hotwired/turbo-rails", to: "turbo.min.js"'
    assert_includes application_js, 'import "@hotwired/turbo-rails"'
    assert_includes application_js, 'import "page_html_preview_addon"'
    assert_includes application_js, 'import * as ActiveStorage from "@rails/activestorage"'
    assert_includes application_js, "ActiveStorage.start()"
  end

  def test_upload_page_supports_optional_registered_upload_providers
    upload_view = File.read(File.expand_path("../app/views/recording_studio_attachable/attachment_uploads/new.html.erb", __dir__))
    initializer_template = File.read(
      File.expand_path(
        "../lib/generators/recording_studio_attachable/install/templates/recording_studio_attachable_initializer.rb",
        __dir__
      )
    )

    assert_includes upload_view, "@upload_providers.any?"
    assert_includes upload_view, "max-w-sm flex-col items-stretch gap-3"
    assert_includes upload_view, "full_width: true"
    assert_includes upload_view, "reverse_merge(full_width: true)"
    assert_includes upload_view, "provider.button_options(view_context: self, recording: @recording, query_params: @upload_redirect_params)"
    assert_includes initializer_template, "config.register_upload_provider("
    assert_includes initializer_template, "config.image_processing_enabled = true"
    assert_includes initializer_template, "config.image_processing_max_width = 2560"
    assert_includes initializer_template, "config.image_processing_quality = 0.82"
    assert_includes initializer_template, "config.image_variants = {"
    assert_includes initializer_template, "square_small: { resize_to_fill: [128, 128] }"
    assert_includes initializer_template, "xlarge: { resize_to_limit: [2400, 2400] }"
    assert_includes initializer_template, 'label: "Google Drive"'
    assert_includes initializer_template, "config.google_drive.enabled = true"
    assert_includes initializer_template, "GOOGLE_DRIVE_CLIENT_ID"
    assert_includes initializer_template, "/recording_studio_attachable/google_drive/oauth/callback"
  end

  def test_dummy_home_demo_includes_registered_demo_cloud_provider
    initializer = File.read(File.expand_path("dummy/config/initializers/recording_studio_attachable.rb", __dir__))
    routes = File.read(File.expand_path("dummy/config/routes.rb", __dir__))
    page_model = File.read(File.expand_path("dummy/app/models/page.rb", __dir__))
    workspace_model = File.read(File.expand_path("dummy/app/models/workspace.rb", __dir__))

    assert_includes initializer, "config.max_file_size = 1.megabyte"
    assert_includes initializer, ":demo_cloud"
    assert_includes initializer, 'label: "Demo cloud import"'
    assert_includes page_model, "max_file_size: 1.megabyte"
    assert_includes workspace_model, "max_file_size: 1.megabyte"
    assert_includes routes, "as: :demo_upload_provider"
  end

  def test_dummy_schema_includes_active_storage_tables_for_direct_uploads
    schema = File.read(File.expand_path("dummy/db/schema.rb", __dir__))

    assert_includes schema, 'create_table "active_storage_blobs"'
    assert_includes schema, 'create_table "active_storage_attachments"'
    assert_includes schema, 'create_table "active_storage_variant_records"'
    assert_includes schema, "idx_rs_attachable_parent_active"
    assert_includes schema, "idx_rs_attachable_root_active"
  end

  def test_dummy_active_storage_can_be_switched_to_amazon_via_environment
    storage = File.read(File.expand_path("dummy/config/storage.yml", __dir__))
    development = File.read(File.expand_path("dummy/config/environments/development.rb", __dir__))
    production = File.read(File.expand_path("dummy/config/environments/production.rb", __dir__))

    assert_includes storage, "amazon:"
    assert_includes storage, "service: S3"
    assert_includes storage, 'ENV["DUMMY_AWS_ACCESS_KEY_ID"]'
    assert_includes storage, 'ENV["DUMMY_AWS_SECRET_ACCESS_KEY"]'
    assert_includes storage, 'ENV.fetch("DUMMY_AWS_REGION", "us-east-1")'
    assert_includes storage, 'ENV["DUMMY_AWS_BUCKET"].to_s.sub(/\Aarn:[^:]+:s3:::+/, "")'
    assert_includes development, 'ENV.fetch("DUMMY_ACTIVE_STORAGE_SERVICE", "local").to_sym'
    assert_includes production, 'ENV.fetch("DUMMY_ACTIVE_STORAGE_SERVICE", "local").to_sym'
  end

  def test_dummy_sidebar_links_to_the_recording_tree_demo_instead_of_recording_studio_root
    sidebar_partial = File.read(File.expand_path("dummy/app/views/layouts/flat_pack/_sidebar.html.erb", __dir__))
    routes = File.read(File.expand_path("dummy/config/routes.rb", __dir__))
    tree_controller = File.read(File.expand_path("dummy/app/controllers/recording_trees_controller.rb", __dir__))
    tree_helper = File.read(File.expand_path("dummy/app/helpers/application_helper.rb", __dir__))
    tree_view = File.read(File.expand_path("dummy/app/views/recording_trees/index.html.erb", __dir__))

    refute_includes sidebar_partial, 'href: "/recording_studio"'
    assert_includes sidebar_partial, 'label: "Recording tree"'
    assert_includes sidebar_partial, "href: recording_tree_path"
    assert_includes routes, 'get "recording_tree", to: "recording_trees#index", as: :recording_tree'
    assert_includes tree_controller, "RecordingStudio::Recording.unscoped.includes(:recordable).order(:created_at).to_a"
    assert_includes tree_helper, "def build_recording_tree_nodes(tree, recordings, recording_children)"
    assert_includes tree_helper, "tree.node(label: recording_tree_label(recording), icon: recording_tree_icon(recording), expanded: children.any?)"
    assert_includes tree_helper, "def recording_tree_icon(recording)"
    assert_includes tree_helper, 'when "Access", "AccessBoundary"'
    assert_includes tree_helper, ":lock"
    assert_includes tree_helper, 'recording.recordable.image? ? :image : :file'
    assert_includes tree_helper, 'when "Page"'
    assert_includes tree_helper, '"document-text"'
    assert_includes tree_view, 'title: "Recording tree"'
    assert_includes tree_view, "render FlatPack::Card::Component.new(style: :default) do |card|"
    assert_includes tree_view, "card.body do"
    assert_includes tree_view, "render FlatPack::Tree::Component.new do |tree|"
    assert_includes tree_view, "build_recording_tree_nodes(tree, @root_recordings, @recording_children)"
    refute_includes tree_view, 'title: "Hierarchy"'
    refute_includes tree_view, "Indented dot points show each child recording beneath its parent."
    refute_includes tree_view, "rounded-xl border border-[var(--surface-border-color)] bg-[var(--surface-background-color)] p-5"
  end
end
