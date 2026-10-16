# frozen_string_literal: true

module RecordingStudioAttachable
  class PurgeUnattachedBlobsJob < ActiveJob::Base
    queue_as :default

    def perform
      cutoff = RecordingStudioAttachable.configuration.unattached_blob_ttl.ago
      ActiveStorage::Blob.unattached.where(created_at: ...cutoff).find_each(&:purge)
    end
  end
end
