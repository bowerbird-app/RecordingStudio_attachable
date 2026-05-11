# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/import_attachment_payloads"
require_relative "../../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../../app/services/recording_studio_attachable/services/record_attachment_uploads"

class ImportAttachmentPayloadsTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

  def setup
    stub_recording_studio!
  end

  def test_call_processes_local_and_remote_payloads_through_shared_services
    parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
    local_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:local])
    provider = Struct.new(:key) do
      def import_remote_attachments(**kwargs)
        self.captured = kwargs
        RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:remote])
      end

      attr_accessor :captured
    end.new(:google_drive)
    captured_local = nil
    request_context = Struct.new(:session).new({})

    RecordingStudioAttachable.configuration.stub(:upload_provider, provider) do
      RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, lambda { |**kwargs|
        captured_local = kwargs
        local_result
      }) do
        result = RecordingStudioAttachable::Services::ImportAttachmentPayloads.call(
          parent_recording: parent,
          actor: :actor,
          impersonator: :impersonator,
          context: request_context,
          attachments: [
            { signed_blob_id: "blob-1", name: "Local file" },
            { provider_key: "google_drive", provider_payload: { id: "file-1" }, name: "Drive file" }
          ]
        )

        assert result.success?
        assert_equal %i[local remote], result.value
      end
    end

    assert_equal "direct_upload", captured_local[:default_source]
    assert_equal [{ signed_blob_id: "blob-1", name: "Local file" }], captured_local[:attachments]
    assert_equal parent, provider.captured[:parent_recording]
    assert_equal :actor, provider.captured[:actor]
    assert_equal :impersonator, provider.captured[:impersonator]
    assert_same request_context, provider.captured[:context]
    assert_equal [{ provider_key: "google_drive", provider_payload: { id: "file-1" }, name: "Drive file" }], provider.captured[:attachments]
  end

  def test_call_uses_provider_key_as_default_source_for_signed_blob_payloads
    parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
    captured = nil

    RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, lambda { |**kwargs|
      captured = kwargs
      RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:created])
    }) do
      result = RecordingStudioAttachable::Services::ImportAttachmentPayloads.call(
        parent_recording: parent,
        attachments: [
          { provider_key: "google_drive", signed_blob_id: "blob-1", name: "Drive handoff" }
        ]
      )

      assert result.success?
    end

    assert_equal "google_drive", captured[:default_source]
  end

  private

  def stub_recording_studio!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.singleton_class.send(:remove_method, :capability_options) if studio.singleton_class.method_defined?(:capability_options)
    studio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
  end
end
