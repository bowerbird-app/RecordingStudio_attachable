# frozen_string_literal: true

require "test_helper"
require_relative "../google_drive_fakes"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../../lib/recording_studio_attachable/google_drive/services/import_selected_files"

class GoogleDriveImportSelectedFilesTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)

  def test_call_downloads_selected_files_and_delegates_to_import_attachments
    captured_ids = []
    client = Object.new
    client.define_singleton_method(:fetch_file) do |file_id, resource_key: nil|
      captured_ids << [file_id, resource_key]
      GoogleDriveFakes::DriveFile.new(
        id: file_id,
        name: "File #{file_id}",
        mime_type: "application/pdf",
        web_view_link: "https://drive.test/#{file_id}"
      )
    end
    client.define_singleton_method(:download) do |file_id, resource_key: nil|
      GoogleDriveFakes::DownloadedFile.new(
        body: "payload",
        filename: "File #{file_id}.pdf",
        content_type: "application/pdf"
      )
    end
    captured = nil
    expected_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:imported])

    RecordingStudioAttachable::GoogleDrive::Integration.stub(:client, client) do
      RecordingStudioAttachable::Services::ImportAttachments.stub(:call, lambda { |**kwargs|
        captured = kwargs
        expected_result
      }) do
        result = RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.call(
          parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
          file_ids: %w[file-1 file-2],
          actor: :actor,
          impersonator: :impersonator
        )

        assert result.success?
        assert_equal [:imported], result.value
      end
    end

    assert_equal [["file-1", nil], ["file-2", nil]], captured_ids
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
      file_ids: []
    )

    assert result.failure?
    assert_equal "Select at least one Google Drive file to import", result.error
  end

  def test_call_builds_a_google_drive_gem_client_when_one_is_not_injected
    client = Object.new
    file = GoogleDriveFakes::DriveFile.new(id: "file-1", name: "File file-1", mime_type: "application/pdf", web_view_link: "https://drive.test/file-1")
    client.define_singleton_method(:fetch_file) { |_id, resource_key: nil| file }
    client.define_singleton_method(:download) do |_id, resource_key: nil|
      GoogleDriveFakes::DownloadedFile.new(body: "payload", filename: "File file-1.pdf", content_type: "application/pdf")
    end
    built_with = nil
    expected_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:imported])
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

    RecordingStudioAttachable::GoogleDrive::Integration.stub(:client, lambda { |root:, actor:|
      built_with = [root, actor]
      client
    }) do
      RecordingStudioAttachable::Services::ImportAttachments.stub(:call, expected_result) do
        result = RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.call(
          parent_recording: recording,
          file_ids: ["file-1"],
          actor: :actor
        )

        assert result.success?
      end
    end

    assert_equal [recording, :actor], built_with
  end

  def test_call_passes_picker_resource_keys_through_to_the_gem_client
    calls = []
    client = Object.new
    client.define_singleton_method(:fetch_file) do |file_id, resource_key: nil|
      calls << [:fetch, file_id, resource_key]
      GoogleDriveFakes::DriveFile.new(id: file_id, name: "File #{file_id}", mime_type: "image/png", web_view_link: "https://drive.test/#{file_id}")
    end
    client.define_singleton_method(:download) do |file_id, resource_key: nil|
      calls << [:download, file_id, resource_key]
      GoogleDriveFakes::DownloadedFile.new(body: "payload", filename: "File #{file_id}.png", content_type: "image/png")
    end

    RecordingStudioAttachable::GoogleDrive::Integration.stub(:client, client) do
      RecordingStudioAttachable::Services::ImportAttachments.stub(
        :call,
        RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:imported])
      ) do
        result = RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.call(
          parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
          file_ids: [{ id: "file-1", resource_key: "resource-key-1" }],
          actor: :actor
        )

        assert result.success?
      end
    end

    assert_equal [:fetch, "file-1", "resource-key-1"], calls.first
    assert_equal [:download, "file-1", "resource-key-1"], calls.last
  end
end
