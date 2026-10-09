# frozen_string_literal: true

module RecordingStudioAttachable
  module StorageRelease
    extend ActiveSupport::Concern

    included do
      attr_accessor :recording_studio_attachable_detached_blob_ids

      before_destroy :recording_studio_attachable_purge_placements, prepend: true
      before_destroy :recording_studio_attachable_detach_storage, prepend: true
      after_commit :recording_studio_attachable_purge_detached_blobs, on: :destroy
    end

    def recording_studio_attachable_purge_placements
      return unless recordable_type == "RecordingStudioAttachable::Attachment"

      RecordingStudioAttachable::Placements.purge_for(self)
    end

    def recording_studio_attachable_detach_storage
      StorageLimit.detach_recording!(self)
    end

    def recording_studio_attachable_purge_detached_blobs
      StorageLimit.purge_detached_blobs!(self)
    end
  end
end
