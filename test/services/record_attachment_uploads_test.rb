# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/record_attachment_uploads"

class RecordAttachmentUploadsTest < Minitest::Test
  def test_returns_failure_without_partial_success_when_a_file_fails
    parent = Struct.new(:id, :recordable_type).new("parent-1", "Workspace")
    upload_service = RecordingStudioAttachable::Services::RecordAttachmentUpload
    success_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: :created)
    failure_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: "bad file")
    calls = []

    upload_service.stub(:call, lambda { |**kwargs|
      calls << kwargs[:signed_blob_id]
      calls.one? ? success_result : failure_result
    }) do
      result = RecordingStudioAttachable::Services::RecordAttachmentUploads.call(
        parent_recording: parent,
        actor: Object.new,
        attachments: [
          { signed_blob_id: "blob-1", name: "one" },
          { signed_blob_id: "blob-2", name: "two" }
        ]
      )

      assert result.failure?
      assert_equal "One or more attachments failed to finalize", result.error
      assert_equal %w[blob-1 blob-2], calls
      assert_equal [{ signed_blob_id: "blob-2", name: "two", error: "bad file" }], result.errors
    end
  end
end
