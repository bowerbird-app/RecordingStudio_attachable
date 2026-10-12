# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../../lib/recording_studio_attachable/google_drive/services/import_selected_files"

class GoogleDriveImportSelectedFilesTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

  def test_call_resolves_selected_files_and_delegates_to_import_attachments
    captured_ids = []
    files = method(:remote_file_for)
    client = Object.new
    client.define_singleton_method(:resolve) do |selection|
      captured_ids << selection.fetch("id")
      files.call(selection.fetch("id"))
    end
    fetched = RecordingStudioAttachable::SafeRemoteFetch::Result.new(
      io: StringIO.new("payload"),
      content_type: "application/pdf",
      byte_size: 7
    )
    captured = nil
    expected_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:imported])

    RecordingStudioAttachable::SafeRemoteFetch.stub(:call, fetched) do
      RecordingStudioAttachable::Services::ImportAttachments.stub(:call, lambda { |**kwargs|
        captured = kwargs
        expected_result
      }) do
        result = RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.call(
          parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
          file_ids: %w[file-1 file-2],
          access_token: "access-token",
          actor: :actor,
          impersonator: :impersonator,
          client: client
        )

        assert result.success?
        assert_equal [:imported], result.value
      end
    end

    assert_equal %w[file-1 file-2], captured_ids
    assert_equal :actor, captured[:actor]
    assert_equal :impersonator, captured[:impersonator]
    assert_equal "google_drive", captured[:source]
    assert_equal 2, captured[:attachments].size
    assert_equal "File file-1", captured[:attachments].first[:name]
    assert_equal "Imported from Google Drive", captured[:attachments].first[:description]
    assert_equal(
      { provider: "google_drive", external_id: "file-1", external_url: "https://drive.test/file-1" },
      captured[:attachments].first[:metadata]
    )
  end

  def test_call_rejects_blank_file_ids
    result = RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.call(
      parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
      file_ids: [],
      access_token: "access-token"
    )

    assert result.failure?
    assert_equal "Select at least one Google Drive file to import", result.error
  end

  def test_call_builds_a_default_google_drive_client_when_one_is_not_injected
    client = Object.new
    file = remote_file_for("file-1")
    client.define_singleton_method(:resolve) { |_selection| file }
    built_with_token = nil
    fetched = RecordingStudioAttachable::SafeRemoteFetch::Result.new(
      io: StringIO.new("payload"),
      content_type: "application/pdf",
      byte_size: 7
    )
    expected_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:imported])

    RecordingStudioAttachable::GoogleDrive::Client.stub(:new, lambda { |access_token:|
      built_with_token = access_token
      client
    }) do
      RecordingStudioAttachable::SafeRemoteFetch.stub(:call, fetched) do
        RecordingStudioAttachable::Services::ImportAttachments.stub(:call, expected_result) do
          result = RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.call(
            parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
            file_ids: ["file-1"],
            access_token: "access-token"
          )

          assert result.success?
        end
      end
    end

    assert_equal "access-token", built_with_token
  end

  def test_call_passes_picker_resource_keys_through_to_resolve
    calls = []
    files = method(:remote_file_for)
    client = Object.new
    client.define_singleton_method(:resolve) do |selection|
      calls << selection
      files.call(selection.fetch("id"), resource_key: selection["resource_key"])
    end
    fetched = RecordingStudioAttachable::SafeRemoteFetch::Result.new(
      io: StringIO.new("payload"),
      content_type: "image/png",
      byte_size: 7
    )

    RecordingStudioAttachable::SafeRemoteFetch.stub(:call, fetched) do
      RecordingStudioAttachable::Services::ImportAttachments.stub(
        :call,
        RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:imported])
      ) do
        result = RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.call(
          parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
          file_ids: [{ id: "file-1", resource_key: "resource-key-1" }],
          access_token: "access-token",
          client: client
        )

        assert result.success?
      end
    end

    assert_equal "file-1", calls.first.fetch("id")
    assert_equal "resource-key-1", calls.first.fetch("resource_key")
  end

  private

  def remote_file_for(file_id, resource_key: nil)
    RecordingStudioAttachable::RemoteFile.new(
      uri: "https://www.googleapis.com/drive/v3/files/#{file_id}?alt=media",
      allowed_hosts: ["www.googleapis.com"],
      filename: "File #{file_id}.pdf",
      content_type: "application/pdf",
      external_id: file_id,
      external_url: "https://drive.test/#{file_id}",
      name: "File #{file_id}",
      headers: resource_key ? { "X-Goog-Drive-Resource-Keys" => resource_key } : {}
    )
  end
end
