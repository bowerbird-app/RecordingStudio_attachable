# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../../app/services/recording_studio_attachable/services/import_remote_files"

class ImportRemoteFilesTest < Minitest::Test
  FakeRecording = Struct.new(:id, keyword_init: true)

  def test_downloads_payloads_stamps_provider_and_closes_io
    parent = FakeRecording.new(id: "parent-1")
    io = StringIO.new("bytes")
    captured = nil
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:ok])

    RecordingStudioAttachable::Services::ImportAttachments.stub(:call, lambda { |**kwargs|
      captured = kwargs
      result
    }) do
      returned = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
        parent_recording: parent,
        provider_key: :my_cloud,
        actor: :actor,
        impersonator: :impersonator,
        payloads: [
          {
            download: -> { { io: io, filename: "brief.png", content_type: "image/png" } },
            filename: "brief.png",
            content_type: "image/png",
            byte_size: 5,
            name: "Brief",
            metadata: { external_id: "file-1", external_url: "https://cloud.test/file-1", extra: "kept" }
          }
        ]
      )

      assert returned.success?
    end

    attachment = captured[:attachments].first
    assert_same parent, captured[:parent_recording]
    assert_equal "my_cloud", captured[:source]
    assert_equal "brief.png", attachment[:filename]
    assert_equal "Brief", attachment[:name]
    assert_equal "file-1", attachment[:metadata][:external_id]
    assert_equal "my_cloud", attachment[:metadata][:provider]
    assert_equal "kept", attachment[:metadata][:extra]
    assert io.closed?
  end

  def test_rejects_oversized_declared_byte_size
    parent = FakeRecording.new(id: "parent-1")
    original_max = RecordingStudioAttachable.configuration.max_file_size
    RecordingStudioAttachable.configuration.max_file_size = 4

    result = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
      parent_recording: parent,
      provider_key: :my_cloud,
      payloads: [{ io: StringIO.new("bytes"), filename: "too-big.bin", byte_size: 5 }]
    )

    refute result.success?
    assert_equal "Remote file exceeds maximum file size", result.error
  ensure
    RecordingStudioAttachable.configuration.max_file_size = original_max
  end
end
