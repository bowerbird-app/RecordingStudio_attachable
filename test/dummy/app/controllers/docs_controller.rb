class DocsController < ApplicationController
  before_action :set_doc_examples

  def setup; end

  def configuration; end

  def methods_reference; end

  def gem_views; end

  private

  def set_doc_examples
    @setup_steps = [
      "Install Active Storage in the host app and run its migrations before using uploads.",
      "Install Recording Studio and RecordingStudio Accessible so authorization works with the default role mapping.",
      "Run the attachable install and migration generators, then migrate the host app schema.",
      "Register RecordingStudioAttachable::Attachment and opt parent recordables into the attachable capability.",
      "Choose a layout in config when you want gem pages to render inside the host app shell instead of the blank layout."
    ]

    @config_example = <<~RUBY
      RecordingStudioAttachable.configure do |config|
        config.allowed_content_types = ["image/*", "application/pdf"]
        config.max_file_size = 25.megabytes
        config.max_file_count = 20
        config.enabled_attachment_kinds = %i[image file]
        config.default_listing_scope = :direct
        config.default_kind_filter = :all

        # Use the gem's blank layout, or point at a host-app layout like "application".
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

        # Keep attachments as direct children unless your host app needs a different placement rule.
        config.placement = :children_only
        config.trashable_required_for_restore = true
      end
    RUBY

    @method_examples = [
      {
        title: "Opt a recordable into attachments",
        subtitle: "RecordingStudio::Capabilities::Attachable.to(...)",
        code: <<~RUBY
          class Workspace < ApplicationRecord
            include RecordingStudio::Capabilities::Attachable.to(
              # Allow images and PDFs for this recordable type.
              allowed_content_types: ["image/*", "application/pdf"],
              # Keep upload batches small and predictable for editors.
              max_file_count: 20
            )
          end
        RUBY
      },
      {
        title: "Link to the attachment listing",
        subtitle: "recording_attachments_path(recording)",
        code: <<~RUBY
          # Use the parent recording to open the listing page provided by the gem.
          recording_attachments_path(@recording, scope: :direct, kind: :all)
        RUBY
      },
      {
        title: "Open the upload flow",
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
      "recording_studio_attachable/recording_attachments/index.html.erb — attachment listing with scope and kind filters",
      "recording_studio_attachable/attachment_uploads/new.html.erb — direct-upload queue and finalize screen",
      "recording_studio_attachable/attachments/show.html.erb — preview, metadata revision, and file replacement flow",
      "layouts/recording_studio_attachable/blank.html.erb — centered blank shell with no top nav or sidebar"
    ]
  end
end
