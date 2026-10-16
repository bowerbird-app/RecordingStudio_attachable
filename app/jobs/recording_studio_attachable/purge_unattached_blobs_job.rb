# frozen_string_literal: true

module RecordingStudioAttachable
  class PurgeUnattachedBlobsJob < ActiveJob::Base
    queue_as :default

    def perform
      return unless RecordingStudioAttachable.configuration.purge_unattached_blobs

      cutoff = RecordingStudioAttachable.configuration.unattached_blob_ttl.ago
      DirectUpload.expired_unattached(cutoff).find_each(&:purge)
    end
  end
end
