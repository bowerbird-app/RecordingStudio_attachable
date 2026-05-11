class DocsController < ApplicationController
  before_action :set_doc_examples

  def setup; end

  def configuration; end

  def methods_reference; end

  def plugins; end

  def picker; end

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
              # Maximum files allowed in one upload or import batch.
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
        # Maximum files allowed in one upload or import batch.
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
      "Providers that need cloud imports should register a remote_importer hook so the shared upload queue can hand normalized remote selections back to addon code without giving up control of the browser flow.",
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
              strategy: :client_picker,
              launcher: "google_drive",
              bootstrap_url: ->(route_helpers:, recording:) do
                route_helpers.google_drive.recording_bootstrap_path(recording, format: :json)
              end,
              remote_importer: lambda do |parent_recording:, attachments:, actor: nil, impersonator: nil, context: nil|
                access_token = GoogleDriveSessionAccessToken.fetch(session: context.session)

                MyAddon::GoogleDrive::ImportSelectedFiles.call(
                  parent_recording: parent_recording,
                  file_ids: attachments.map { |payload| payload.fetch(:provider_payload) },
                  access_token: access_token,
                  actor: actor,
                  impersonator: impersonator
                )
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
            # identify defaults to true; only disable it for trusted providers
            # that already verified the file metadata out of band.
            source: "google_drive",
            metadata: { external_id: remote_file.id }
          )
        RUBY
      },
      {
        title: "Register the remote importer hook",
        subtitle: "provider.import_remote_attachments(...) via remote_importer:",
        language: :ruby,
        code: <<~RUBY
          remote_importer = lambda do |parent_recording:, attachments:, actor: nil, impersonator: nil, context: nil|
            access_token = GoogleDriveSessionAccessToken.fetch(session: context.session)

            MyAddon::GoogleDrive::ImportSelectedFiles.call(
              parent_recording: parent_recording,
              file_ids: attachments.map { |payload| payload.fetch(:provider_payload) },
              access_token: access_token,
              actor: actor,
              impersonator: impersonator
            )
          end
        RUBY
      }
    ]

    @plugin_api_points = [
      "Upload discovery: config.register_upload_provider(key, label:, strategy:, bootstrap_url:, launcher:, remote_importer:, icon:, visible:, target:). Prefer route_helpers: in callables instead of reaching into the full view context.",
      "remote_importer is the public cloud-provider hook. It receives parent_recording:, attachments:, actor:, impersonator:, and context:, then returns the standard service result object.",
      "Direct import services: RecordingStudioAttachable::Services::ImportAttachment.call and ImportAttachments.call.",
      "Convenience recording helpers exist for trusted internal app code, but addon gems should prefer the explicit service result APIs.",
      "Browser handoff endpoint: recording_attachment_imports_path(recording) for multipart file uploads, signed_blob_id finalization, and shared-queue remote selections inside the host app session.",
      "Provider provenance for the HTTP endpoint comes from provider_key; callers can add metadata, but they do not choose source or storage service.",
      "max_file_count is enforced per upload/import batch. If you need a total-per-recording quota, add that policy in host app code."
    ]

    @plugin_payload_fields = [
      "file: multipart upload when the provider callback already has a local file in hand.",
      "signed_blob_id: finalize an existing Active Storage blob without re-uploading it.",
      "provider_payload: opaque provider-specific selection data handed back to remote_importer from the shared upload queue.",
      "io, filename, content_type: the direct service-level import contract for provider integrations.",
      "name and description: optional attachment metadata overrides.",
      "metadata: extra provider details such as external ids or URLs.",
      "source and identify: trusted direct-service options; identify defaults to true, and the HTTP endpoint stamps source from provider_key and ignores storage-service overrides."
    ]

    @picker_summary = [
      "The picker is an image-only library surface backed by recording_attachment_picker_path(recording). The endpoint filters to kind: :images and returns JSON cards plus pagination.",
      "The bundled Stimulus controller loads that JSON into a FlatPack modal, supports search, infinite scroll, direct uploads, and single or multiple selection.",
      "Every selection dispatches a recording-studio-attachable--attachment-image-picker:selected event with event.detail.attachment so host-app code can persist or render the chosen attachment.",
      "The same payload shape is returned after new uploads, so browsing existing images and uploading new images share one client contract."
    ]

    @picker_payload_fields = [
      "id: the attachment recording id to persist on host-app records or form payloads.",
      "name, description, content_type, byte_size, attachment_kind: display metadata for cards, previews, and audit UI.",
      "thumbnail_url: square preview for gallery cards and compact chip UIs.",
      "insert_url and variant_urls: original and size-specific URLs for inline image rendering.",
      "alt and show_path: host-app accessible text and a stable detail link for the attachment."
    ]

    @picker_usage_examples = [
      {
        title: "Expose the picker endpoint for a parent recording",
        subtitle: "Controller setup for a host-app screen",
        language: :ruby,
        code: <<~RUBY
          class PagesController < ApplicationController
            def edit
              @page = Page.find(params[:id])
              @page_recording = RecordingStudio::Recording.unscoped.find_by!(recordable: @page)

              @page_attachment_picker_path =
                recording_studio_attachable.recording_attachment_picker_path(@page_recording)
              @page_attachment_create_path =
                recording_studio_attachable.recording_attachment_imports_path(@page_recording)
            end
          end
        RUBY
      },
      {
        title: "Listen for selected attachments in app UI",
        subtitle: "Event-driven integration for chat, chips, or custom forms",
        language: :erb,
        code: <<~ERB
          <div
            data-controller="chat-demo recording-studio-attachable--attachment-image-picker"
            data-action="recording-studio-attachable--attachment-image-picker:selected->chat-demo#attachmentSelected"
            data-recording-studio-attachable--attachment-image-picker-picker-url-value="<%= @chat_attachment_picker_path %>"
            data-recording-studio-attachable--attachment-image-picker-upload-url-value="<%= @chat_attachment_create_path %>"
            data-recording-studio-attachable--attachment-image-picker-direct-upload-url-value="<%= main_app.rails_direct_uploads_path %>">
          </div>
        ERB
      },
      {
        title: "Read the returned attachment payload",
        subtitle: "Stimulus consumer contract",
        language: :js,
        code: <<~JAVASCRIPT
          async attachmentSelected(event) {
            const { attachment } = event.detail || {}
            if (!attachment) return

            await this.persistAttachment(attachment.id)
            this.renderAttachmentChip({
              id: attachment.id,
              name: attachment.name,
              thumbnailUrl: attachment.thumbnail_url,
              fileUrl: attachment.insert_url,
              showPath: attachment.show_path
            })
          }
        JAVASCRIPT
      },
      {
        title: "Reuse the picker from the inline editor toolbar",
        subtitle: "The bundled controller can also insert selected images into Tiptap",
        language: :erb,
        code: <<~ERB
          <div
            data-controller="recording-studio-attachable--attachment-image-picker"
            data-action="recording-studio-inline-picker->recording-studio-attachable--attachment-image-picker#openPickerFromToolbar"
            data-recording-studio-attachable--attachment-image-picker-picker-url-value="<%= @page_attachment_picker_path %>"
            data-recording-studio-attachable--attachment-image-picker-upload-url-value="<%= @page_attachment_create_path %>"
            data-recording-studio-attachable--attachment-image-picker-modal-id-value="page-image-picker-modal">
          </div>
        ERB
      }
    ]

    @picker_integration_notes = [
      "Use the event contract when your app owns what happens after selection, such as attaching images to a draft message, form field, or custom chip list.",
      "Use the toolbar hook when you want the bundled controller to insert the chosen image into the FlatPack rich-text editor automatically.",
      "Pass scope: :subtree when a screen should browse images owned anywhere below a root recording, such as a workspace-level chat demo.",
      "Keep the picker and your host-app action separate: the picker chooses or uploads an attachment, while your app decides whether to insert, persist, preview, or send it."
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
