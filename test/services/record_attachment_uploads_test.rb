# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/record_attachment_uploads"

class RecordAttachmentUploadsTest < Minitest::Test
  def setup
    stub_recording_studio!
  end

  def test_returns_failure_without_partial_success_when_a_file_fails
    parent = Struct.new(:id, :recordable_type).new("parent-1", "Workspace")
    upload_service = RecordingStudioAttachable::Services::RecordAttachmentUpload
    success_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: :created)
    failure_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: "bad file")
    signed_blob_ids = []

    upload_service.stub(:call, lambda { |**kwargs|
      signed_blob_ids << kwargs[:signed_blob_id]
      signed_blob_ids.one? ? success_result : failure_result
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
      assert_equal %w[blob-1 blob-2], signed_blob_ids
      assert_equal [{ signed_blob_id: "blob-2", name: "two", error: "bad file" }], result.errors
    end
  end

  def test_returns_failure_when_batch_exceeds_max_file_count
    parent = Struct.new(:id, :recordable_type).new("parent-1", "Workspace")

    RecordingStudio.stub(:capability_options, { max_file_count: 1 }) do
      result = RecordingStudioAttachable::Services::RecordAttachmentUploads.call(
        parent_recording: parent,
        actor: Object.new,
        attachments: [
          { signed_blob_id: "blob-1", name: "one" },
          { signed_blob_id: "blob-2", name: "two" }
        ]
      )

      assert result.failure?
      assert_equal "You can upload up to 1 file at a time", result.error
    end
  end

  private

  def stub_recording_studio!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.singleton_class.send(:remove_method, :capability_options) if studio.singleton_class.method_defined?(:capability_options)
    studio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
  end
end
