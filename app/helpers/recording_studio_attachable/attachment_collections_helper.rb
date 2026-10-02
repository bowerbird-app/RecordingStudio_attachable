# frozen_string_literal: true

require "recording_studio_attachable/attachment_collection"
require "recording_studio_attachable/attachment_file_button"

module RecordingStudioAttachable
  module AttachmentCollectionsHelper
    def attachment_collection_editor(recording, association:, fields:, sortable: false, url: nil, return_to: nil)
      collection = AttachmentCollection.for(recording:, association:, fields:, sortable:, return_to:)
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
