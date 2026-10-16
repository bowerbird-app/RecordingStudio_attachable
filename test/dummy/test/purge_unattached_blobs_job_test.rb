# frozen_string_literal: true

require "test_helper"
require "base64"
require "digest"

class PurgeUnattachedBlobsJobTest < ActiveSupport::TestCase
  setup do
    @purge = RecordingStudioAttachable.configuration.purge_unattached_blobs
    RecordingStudioAttachable.configuration.purge_unattached_blobs = true
  end

  teardown do
    RecordingStudioAttachable.configuration.purge_unattached_blobs = @purge
  end

  test "deletes old unattached blobs this gem created and keeps fresh, attached, or foreign blobs" do
    old_blob = blob_at(2.days.ago)
    fresh_blob = blob_at(1.hour.ago)
    attached_blob = blob_at(3.days.ago)
    foreign_blob = blob_at(3.days.ago, tagged: false)
    keeper = User.create!(
      email: "keeper-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: "Keeper"
    )
    ActiveStorage::Attachment.create!(name: "file", record: keeper, blob: attached_blob)

    RecordingStudioAttachable::PurgeUnattachedBlobsJob.perform_now

    assert_nil ActiveStorage::Blob.find_by(id: old_blob.id)
    assert ActiveStorage::Blob.find_by(id: fresh_blob.id)
    assert ActiveStorage::Blob.find_by(id: attached_blob.id)
    assert ActiveStorage::Blob.find_by(id: foreign_blob.id)
  end

  test "does nothing until the host opts in" do
    RecordingStudioAttachable.configuration.purge_unattached_blobs = false
    old_blob = blob_at(2.days.ago)

    RecordingStudioAttachable::PurgeUnattachedBlobsJob.perform_now

    assert ActiveStorage::Blob.find_by(id: old_blob.id)
  end

  private

  def blob_at(time, tagged: true)
    bytes = "file-#{time.to_i}-#{tagged}"
    metadata = tagged ? { RecordingStudioAttachable::DirectUpload::TAG => "1" } : {}
    ActiveStorage::Blob.create_before_direct_upload!(
      filename: "file.png",
      byte_size: bytes.bytesize,
      checksum: Base64.strict_encode64(Digest::MD5.digest(bytes)),
      content_type: "image/png",
      metadata: metadata
    ).tap { |blob| blob.update_columns(created_at: time) }
  end
end
