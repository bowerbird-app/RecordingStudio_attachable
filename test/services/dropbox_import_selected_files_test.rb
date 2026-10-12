# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../../lib/recording_studio_attachable/dropbox/services/import_selected_files"

class DropboxImportSelectedFilesTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

  def test_call_resolves_ids_fetches_safely_and_delegates_to_import_attachments
    remote_file = RecordingStudioAttachable::RemoteFile.new(
      uri: "https://content.dropboxapi.com/2/files/download",
      allowed_hosts: ["content.dropboxapi.com"],
      filename: "Brief.pdf",
      content_type: "application/pdf",
      external_id: "id:file-1",
      name: "Brief"
    )
    client = Object.new
    client.define_singleton_method(:resolve) { |_selection| remote_file }
    fetched = RecordingStudioAttachable::SafeRemoteFetch::Result.new(
      io: StringIO.new("pdf-bytes"),
      content_type: "application/pdf",
      byte_size: 9
    )
    captured = nil
    expected_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:imported])

    RecordingStudioAttachable::SafeRemoteFetch.stub(:call, fetched) do
      RecordingStudioAttachable::Services::ImportAttachments.stub(:call, lambda { |**kwargs|
        captured = kwargs
        expected_result
      }) do
        result = RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.call(
          parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
          file_ids: ["file-1"],
          access_token: "access-token",
          actor: :actor,
          impersonator: :impersonator,
          client: client
        )

        assert result.success?
      end
    end

    assert_equal "dropbox", captured[:source]
    assert_equal "Brief.pdf", captured[:attachments].first[:filename]
    assert_equal(
      { provider: "dropbox", external_id: "id:file-1" },
      captured[:attachments].first[:metadata]
    )
  end

  def test_call_rejects_blank_file_ids
    result = RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.call(
      parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
      file_ids: [],
      access_token: "access-token"
    )

    assert result.failure?
    assert_equal "Select at least one Dropbox file to import", result.error
  end
end
