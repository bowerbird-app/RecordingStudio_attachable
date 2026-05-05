class DocsController < ApplicationController
  before_action :set_doc_examples

  def setup; end

  def configuration; end

  def methods_reference; end

  def gem_views; end

  private

  def set_doc_examples
    @setup_prerequisites = [
      "Ruby 3.3+ and Rails 8.1+ in the host app.",
      "Recording Studio installed in the host app.",
      "RecordingStudio Accessible installed for the default authorization adapter.",
      "RecordingStudio Trashable installed if you want restore support for removed attachments."
    ]

    @setup_steps = [
      {
        title: "Add the gem to the host app",
        body: "Bundle the gem first so the install and migration generators are available in the host app.",
        code_title: "Gemfile",
        code: <<~RUBY
          gem "recording_studio_attachable"
        RUBY
      },
      {
        title: "Install Active Storage before uploads",
        body: "The gem stores files with Active Storage and depends on the direct-upload pipeline being available before editors can attach files.",
        code_title: "Set up Active Storage",
        code: <<~BASH
          bin/rails active_storage:install
          bin/rails db:migrate
        BASH
      },
      {
        title: "Run the attachable generators",
        body: "The install generator mounts the engine, creates the initializer, pins @rails/activestorage, starts Active Storage in application.js, and eager-loads the gem Stimulus controllers.",
        code_title: "Install and migrate the gem",
        code: <<~BASH
          bin/rails generate recording_studio_attachable:install
          bin/rails generate recording_studio_attachable:migrations
          bin/rails db:migrate
        BASH
      },
      {
        title: "Register the attachment recordable",
        body: "Recording Studio must know about the addon-owned attachment recordable so child attachment recordings can be created and displayed correctly.",
        code_title: "config/initializers/recording_studio.rb",
        code: <<~RUBY
          RecordingStudio.configure do |config|
            config.recordable_types << "RecordingStudioAttachable::Attachment"
          end
        RUBY
      },
      {
        title: "Opt parent models into the attachable capability",
        body: "Include the capability on any recordable model that should expose the attachment library and upload flow.",
        code_title: "app/models/workspace.rb",
        code: <<~RUBY
          class Workspace < ApplicationRecord
            include RecordingStudio::Capabilities::Attachable.to(
              allowed_content_types: ["image/*", "application/pdf", "text/plain"],
              max_file_size: 25.megabytes,
              max_file_count: 20,
              enabled_attachment_kinds: %i[image file]
            )
          end
        RUBY
      }
    ]

    @active_storage_checks = [
      "@rails/activestorage is pinned in config/importmap.rb.",
      "ActiveStorage.start() runs in app/javascript/application.js.",
      "controllers/recording_studio_attachable is eager-loaded from app/javascript/controllers/index.js.",
      "A storage service is configured for each environment before testing uploads."
    ]

    @setup_next_steps = [
      "Review the generated recording_studio_attachable initializer if you need a host-app layout instead of the blank layout.",
      "Visit the upload flow in the dummy app to confirm direct uploads and authorization behave as expected.",
      "Make sure Active Storage, Recording Studio, and this gem's migrations are all applied before debugging missing attachments."
    ]

    @config_example = <<~RUBY
      RecordingStudioAttachable.configure do |config|
        config.allowed_content_types = ["image/*", "application/pdf"]
        config.max_file_size = 25.megabytes
        config.max_file_count = 20
        config.enabled_attachment_kinds = %i[image file]
        config.default_listing_scope = :direct
        config.default_kind_filter = :all

        # Use the gem's blank layout, or point at a host app layout like "application".
        config.layout = :blank

        # Map attachable actions to the roles your authorization adapter understands.
        config.auth_roles = {
          view: :view,
          upload: :edit,
          revise: :edit,
          remove: :admin,
          restore: :admin,
          download: :view
        }
      end
    RUBY

    @method_examples = [
      {
        title: "Library path",
        subtitle: "recording_attachments_path(recording)",
        code: <<~RUBY
          # Use the parent recording to open the listing page provided by the gem.
          recording_attachments_path(@recording, scope: :direct, kind: :all)
        RUBY
      },
      {
        title: "Upload path",
        subtitle: "recording_attachment_upload_path(recording)",
        code: <<~RUBY
          # Send editors to the dedicated direct-upload page for the parent recording.
          recording_attachment_upload_path(@recording)
        RUBY
      },
      {
        title: "Show a specific attachment revision",
        subtitle: "attachment_path(attachment_recording)",
        code: <<~RUBY
          # Use the child attachment recording when linking to the detail page.
          attachment_path(@attachment_recording)
        RUBY
      }
    ]

    @gem_views = [
      {
        title: "Media library",
        path: "recording_studio_attachable/recording_attachments/index.html.erb",
        description: "Browse the attachment library and manage uploads with bulk remove actions.",
        example: "Use it to review uploaded images, PDFs, and other attached files for a recording.",
        icon: :folder
      },
      {
        title: "Upload attachments",
        path: "recording_studio_attachable/attachment_uploads/new.html.erb",
        description: "Upload images and files with the direct-upload queue and finalize flow.",
        example: "Use it when editors need to drag in screenshots, photos, or documents from the host app.",
        icon: :upload
      },
      {
        title: "Attachment details",
        path: "recording_studio_attachable/attachments/show.html.erb",
        description: "Preview an attachment, edit metadata, replace the file, and download or remove the current revision.",
        example: "Use it to inspect a single image or document before revising it.",
        icon: :activity
      },
      {
        title: "Blank layout",
        path: "layouts/recording_studio_attachable/blank.html.erb",
        description: "Render gem pages inside a centered shell with no host-app top nav or sidebar.",
        example: "Use it when the attachment flow should stay isolated from the host application's chrome.",
        icon: :layout
      }
    ]
  end
end
