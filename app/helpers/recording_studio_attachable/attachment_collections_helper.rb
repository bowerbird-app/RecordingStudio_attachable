# frozen_string_literal: true

require "recording_studio_attachable/attachment_collection"
require "recording_studio_attachable/attachment_file_button"
require "recording_studio_attachable/attachment_file_facts"

module RecordingStudioAttachable
  module AttachmentCollectionsHelper
    def attachment_collection_editor(
      recording,
      association:,
      fields:,
      sortable: false,
      preview: :square,
      displays: [:list],
      default_display: nil,
      side_preview: false,
      items_per_view: 1,
      url: nil,
      return_to: nil
    )
      collection = AttachmentCollection.for(
        recording:, association:, fields:, sortable:, preview:, displays:, default_display:, side_preview:, items_per_view:, return_to:
      )
      render partial: "recording_studio_attachable/attachment_collections/editor",
             locals: editor_locals(collection, recording, url, return_to)
    end

    def attachable_attachment_collection_path(recording, **options)
      attachable_routes.recording_attachment_collection_path(recording, **options)
    end

    def attachable_destroy_attachment_path(recording, **options)
      attachable_routes.destroy_attachment_path(recording, **options)
    end

    private

    def editor_locals(collection, recording, url, return_to)
      {
        collection: collection,
        url: url.presence || attachable_attachment_collection_path(recording),
        return_to: return_to
      }
    end
  end
end
