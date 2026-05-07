class DocsController < ApplicationController
  before_action :set_doc_examples

  def setup; end

  def configuration; end

  def methods_reference; end

  def plugins; end

  def resizing; end

  def gem_views; end

  def query; end

  def recordables
    @recordable_types = configured_recordable_types.map do |recordable_type|
      {
        name: recordable_type,
        recordings_count: RecordingStudio::Recording.unscoped.where(recordable_type: recordable_type).count,
        recordables_count: recordable_records_count(recordable_type)
      }
    end
  end

  private

  def configured_recordable_types
    return [] unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:configuration)

    Array(RecordingStudio.configuration.recordable_types).uniq
  end

  def recordable_records_count(recordable_type)
    model = recordable_type.safe_constantize
    return 0 unless model.is_a?(Class) && model < ActiveRecord::Base

    model.unscoped.count
  rescue StandardError
    0
  end

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

        # Optional browser-side image preprocessing before direct upload.
        # JPEG, PNG, and WebP images are resized to fit these bounds.
        # GIF, SVG, HEIC/HEIF, and unsupported image types upload unchanged.
        # config.image_processing_enabled = true
        # config.image_processing_max_width = 2560
        # config.image_processing_max_height = 2560
        # config.image_processing_quality = 0.82

        # Optional server-side image delivery variants. The original blob is kept
        # as uploaded, and generated variants are stored in the same Active Storage
        # service as the source blob.
        # config.image_variants = {
        #   square_small: { resize_to_fill: [128, 128] },
        #   square_med: { resize_to_fill: [400, 400] },
        #   square_large: { resize_to_fill: [800, 800] },
        #   small: { resize_to_limit: [480, 480] },
        #   med: { resize_to_limit: [960, 960] },
        #   large: { resize_to_limit: [1600, 1600] },
        #   xlarge: { resize_to_limit: [2400, 2400] }
        # }

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

    @plugin_summary = [
      "Third-party addons register upload sources with config.register_upload_provider(...) so the upload page can discover them without replacing the built-in direct uploader.",
      "Provider code should usually call the import services directly; the engine-owned recording_attachment_imports_path(recording) endpoint is for browser handoff flows that already run inside the host app.",
      "The gem owns authorization, Active Storage validation, attachment-recording creation, and provider provenance once the provider hands over a file IO or signed blob id.",
      "The built-in Google Drive addon in the dummy app demonstrates the same provider registration and import flow that third-party addons can implement in their own engines or services."
    ]

    @plugin_api_examples = [
      {
        title: "Register a provider button",
        subtitle: "config.register_upload_provider(...)",
        language: :ruby,
        code: <<~RUBY
          RecordingStudioAttachable.configure do |config|
            config.register_upload_provider(
              :google_drive,
              label: "Google Drive",
              icon: "cloud",
              url: ->(route_helpers:, recording:) do
                route_helpers.google_drive_imports_path(recording_id: recording.id)
              end
            )
          end
        RUBY
      },
      {
        title: "Import a provider file directly",
        subtitle: "RecordingStudioAttachable::Services::ImportAttachment.call",
        language: :ruby,
        code: <<~RUBY
          result = RecordingStudioAttachable::Services::ImportAttachment.call(
            parent_recording: recording,
            io: downloaded_file,
            filename: remote_file.name,
            content_type: remote_file.mime_type,
            actor: Current.actor,
            impersonator: Current.impersonator,
            name: remote_file.title,
            source: "google_drive",
            metadata: { external_id: remote_file.id }
          )
        RUBY
      },
      {
        title: "Post browser handoff payloads to the engine",
        subtitle: "recording_attachment_imports_path(recording)",
        language: :ruby,
        code: <<~RUBY
          post recording_studio_attachable.recording_attachment_imports_path(recording), params: {
            attachment_import: {
              provider_key: "google_drive",
              attachments: [
                {
                  signed_blob_id: blob.signed_id,
                  name: remote_file.title,
                  metadata: {
                    external_id: remote_file.id,
                    external_url: remote_file.web_view_link
                  }
                }
              ]
            }
          }, as: :json
        RUBY
      }
    ]

    @plugin_api_points = [
      "Upload discovery: config.register_upload_provider(key, label:, url:, icon:, visible:, target:). Prefer route_helpers: in callables instead of reaching into the full view context.",
      "Direct import services: RecordingStudioAttachable::Services::ImportAttachment.call and ImportAttachments.call.",
      "Convenience recording helpers exist for trusted internal app code, but addon gems should prefer the explicit service result APIs.",
      "Browser handoff endpoint: recording_attachment_imports_path(recording) for multipart file uploads or signed_blob_id finalization inside the host app session.",
      "Provider provenance for the HTTP endpoint comes from provider_key; callers can add metadata, but they do not choose source or storage service."
    ]

    @plugin_payload_fields = [
      "file: multipart upload when the provider callback already has a local file in hand.",
      "signed_blob_id: finalize an existing Active Storage blob without re-uploading it.",
      "io, filename, content_type: the direct service-level import contract for provider integrations.",
      "name and description: optional attachment metadata overrides.",
      "metadata: extra provider details such as external ids or URLs.",
      "source and identify: trusted direct-service options; the HTTP endpoint stamps source from provider_key and ignores storage-service overrides."
    ]

    @resizing_config_example = <<~RUBY
      RecordingStudioAttachable.configure do |config|
        config.image_processing_enabled = true
        config.image_processing_max_width = 2560
        config.image_processing_max_height = 2560
        config.image_processing_quality = 0.82
      end
    RUBY

    @variant_config_example = <<~RUBY
      RecordingStudioAttachable.configure do |config|
        config.image_variants = {
          square_small: { resize_to_fill: [128, 128] },
          square_med: { resize_to_fill: [400, 400] },
          square_large: { resize_to_fill: [800, 800] },
          small: { resize_to_limit: [480, 480] },
          med: { resize_to_limit: [960, 960] },
          large: { resize_to_limit: [1600, 1600] },
          xlarge: { resize_to_limit: [2400, 2400] }
        }

        # Variants are generated on demand the first time a given size is requested.
        # After that, Active Storage stores the processed file in the same service
        # as the original blob, such as S3, and reuses it on later requests.

        # Each size gets its own signed variant URL, so swapping "small" for
        # "large" is not a matter of guessing a simple filename pattern.
        # Treat those signed URLs as delivery identifiers, not as your auth layer.
      end
    RUBY

    @gem_views = [
      {
        title: "Library",
        path: "recording_studio_attachable/recording_attachments/index.html.erb",
        description: "Browse the attachment library and manage uploads with bulk remove actions.",
        example: "Use it to review uploaded images, PDFs, and other attached files for a recording.",
        icon: :grid
      },
      {
        title: "Upload",
        path: "recording_studio_attachable/attachment_uploads/new.html.erb",
        description: "Upload images and files with the direct-upload queue and finalize flow.",
        example: "Use it when editors need to drag in screenshots, photos, or documents from the host app.",
        icon: :upload
      },
      {
        title: "Attachment details",
        path: "recording_studio_attachable/attachments/show.html.erb",
        description: "Show a single attachment with minimal navigation and image preview context.",
        example: "Use it to inspect an image attachment without extra editing controls.",
        icon: :eye
      },
      {
        title: "Blank layout",
        path: "layouts/recording_studio_attachable/blank.html.erb",
        description: "Render gem pages inside a centered shell with no host-app top nav or sidebar.",
        example: "Use it when the attachment flow should stay isolated from the host application's chrome.",
        icon: :layout
      }
    ]

    @query_example = <<~RUBY
      target_recordable_type = "Page" # e.g. "Workspace", "Project", "Post"

      recordings_with_images = RecordingStudioAttachable::Queries::WithAttachments.new(
        recordable_type: target_recordable_type,
        kind: :images
      ).call

      records_with_images = target_recordable_type.constantize.where(
        id: recordings_with_images.select(:recordable_id)
      )
    RUBY
  end
end
