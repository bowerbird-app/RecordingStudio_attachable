# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../../lib/recording_studio_attachable/google_drive/services/import_selected_files"

class GoogleDriveImportSelectedFilesTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

  def test_call_downloads_selected_files_and_delegates_to_import_attachments
    client = Object.new
    client.define_singleton_method(:fetch_file) do |file_id|
      {
        "id" => file_id,
        "name" => "File #{file_id}",
        "mimeType" => "application/pdf",
        "webViewLink" => "https://drive.test/#{file_id}"
      }
    end
    client.define_singleton_method(:download_file) do |file|
      {
        io: StringIO.new("payload-for-#{file.fetch('id')}"),
        filename: "#{file.fetch('name')}.pdf",
        content_type: "application/pdf"
      }
    end
    captured = nil
    expected_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:imported])

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
    client.define_singleton_method(:fetch_file) do |_file_id|
      { "id" => "file-1", "name" => "First", "mimeType" => "application/pdf" }
    end
    client.define_singleton_method(:download_file) do |_file|
      { io: StringIO.new("payload"), filename: "first.pdf", content_type: "application/pdf" }
    end
    built_with_token = nil
    expected_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:imported])

    RecordingStudioAttachable::GoogleDrive::Client.stub(:new, lambda { |access_token:|
      built_with_token = access_token
      client
    }) do
      RecordingStudioAttachable::Services::ImportAttachments.stub(:call, expected_result) do
        result = RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.call(
          parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
          file_ids: ["file-1"],
          access_token: "access-token"
        )

        assert result.success?
      end
    end

    assert_equal "access-token", built_with_token
  end

  def test_call_passes_picker_resource_keys_through_to_the_google_drive_client
    calls = []
    client = Object.new
    client.define_singleton_method(:fetch_file) do |file_id, resource_key: nil|
      calls << { method: :fetch_file, file_id: file_id, resource_key: resource_key }
      {
        "id" => file_id,
        "name" => "File #{file_id}",
        "mimeType" => "image/png",
        "resourceKey" => resource_key,
        "webViewLink" => "https://drive.test/#{file_id}"
      }
    end
    client.define_singleton_method(:download_file) do |file|
      calls << { method: :download_file, resource_key: file["resourceKey"] }
      { io: StringIO.new("payload"), filename: "image.png", content_type: "image/png" }
    end

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

    assert_equal(
      [
        { method: :fetch_file, file_id: "file-1", resource_key: "resource-key-1" },
        { method: :download_file, resource_key: "resource-key-1" }
      ],
      calls
    )
  end
end
