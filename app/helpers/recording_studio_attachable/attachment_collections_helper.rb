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
      items: nil,
      empty_message: nil,
      url: nil,
      return_to: nil
    )
      collection = AttachmentCollection.for(
        recording:, association:, fields:, sortable:, preview:, displays:, default_display:,
        side_preview:, items_per_view:, return_to:, items:, empty_message:
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

    def attachable_destroy_placement_path(recording, **options)
      attachable_routes.destroy_placement_path(recording, **options)
    end

    def attachment_collection_remove_path(collection, row, return_to:)
      params = AttachmentFileButton.redirect_params(return_to: return_to)
      if collection.placement?
        attachable_destroy_placement_path(row.member, **params)
      else
        attachable_destroy_attachment_path(row.recording, **params)
      end
    end

    def attachment_collection_image_path(_collection, row, return_to:)
      attachable_attachment_path(row.recording, **AttachmentFileButton.redirect_params(return_to: return_to))
    end

    def attachment_collection_save_path(collection, recording, url)
      return url if url.present?
      return attachable_routes.recording_placements_path(recording) if collection.placement?

      attachable_attachment_collection_path(recording)
    end

    private

    def editor_locals(collection, recording, url, return_to)
      {
        collection: collection,
        url: attachment_collection_save_path(collection, recording, url),
        return_to: return_to
      }
    end
  end
end
