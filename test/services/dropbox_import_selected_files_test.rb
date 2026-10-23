# frozen_string_literal: true

require "test_helper"
require_relative "../dropbox_fakes"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../../lib/recording_studio_attachable/dropbox/services/import_selected_files"

class DropboxImportSelectedFilesTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)

  def test_call_downloads_selected_files_and_delegates_to_import_attachments
    captured_paths = []
    client = Object.new
    client.define_singleton_method(:fetch_file) do |path:|
      captured_paths << path
      DropboxFakes::DropboxFile.new(
        id: path,
        name: "File #{path}",
        path: "/#{path}"
      )
    end
    client.define_singleton_method(:download) do |path:|
      DropboxFakes::DownloadedFile.new(
        body: "payload",
        filename: "File #{path}.pdf",
        content_type: nil
      )
    end
    captured = nil
    expected_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:imported])

    RecordingStudioAttachable::Dropbox::Integration.stub(:client, client) do
      RecordingStudioAttachable::Services::ImportAttachments.stub(:call, lambda { |**kwargs|
        captured = kwargs
        expected_result
      }) do
        result = RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.call(
          parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
          file_ids: %w[file-1 file-2],
          actor: :actor,
          impersonator: :impersonator
        )

        assert result.success?
        assert_equal [:imported], result.value
      end
    end

    assert_equal %w[file-1 file-2], captured_paths
    assert_equal :actor, captured[:actor]
    assert_equal :impersonator, captured[:impersonator]
    assert_equal "dropbox", captured[:source]
    assert_equal 2, captured[:attachments].size
    assert_equal "File file-1", captured[:attachments].first[:name]
    assert_equal "Imported from Dropbox", captured[:attachments].first[:description]
    assert_equal "application/pdf", captured[:attachments].first[:content_type]
    assert_equal(
      { provider: "dropbox", external_id: "file-1", external_url: "/file-1" },
      captured[:attachments].first[:metadata]
    )
  end

  def test_call_normalizes_hash_selections_and_merges_metadata
    captured_paths = []
    client = Object.new
    client.define_singleton_method(:fetch_file) do |path:|
      captured_paths << path
      DropboxFakes::DropboxFile.new(
        id: "id:#{path}",
        name: "Brief.pdf",
        path: "/Brief.pdf"
      )
    end
    client.define_singleton_method(:download) do |path:|
      DropboxFakes::DownloadedFile.new(
        body: "pdf-bytes",
        filename: "Brief.pdf",
        content_type: "application/pdf"
      )
    end
    captured = nil

    RecordingStudioAttachable::Dropbox::Integration.stub(:client, client) do
      RecordingStudioAttachable::Services::ImportAttachments.stub(:call, lambda { |**kwargs|
        captured = kwargs
        RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:imported])
      }) do
        result = RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.call(
          parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
          file_ids: [
            "",
            { "id" => "file-1", "name" => "Brief", "description" => "Notes", "metadata" => { "folder" => "inbox" } },
            { id: "" }
          ]
        )

        assert result.success?
      end
    end

    assert_equal %w[file-1], captured_paths
    attachment = captured[:attachments].first
    assert_equal "Brief", attachment[:name]
    assert_equal "Notes", attachment[:description]
    assert_equal "application/pdf", attachment[:content_type]
    assert_equal(
      { provider: "dropbox", external_id: "id:file-1", external_url: "/Brief.pdf", "folder" => "inbox" },
      attachment[:metadata]
    )
  end

  def test_call_rejects_blank_file_ids
    result = RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.call(
      parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
      file_ids: []
    )

    assert result.failure?
    assert_equal "Select at least one Dropbox file to import", result.error
  end

  def test_call_builds_a_dropbox_gem_client_when_one_is_not_injected
    client = Object.new
    file = DropboxFakes::DropboxFile.new(id: "file-1", name: "File file-1", path: "/file-1")
    client.define_singleton_method(:fetch_file) { |path:| file }
    client.define_singleton_method(:download) do |path:|
      DropboxFakes::DownloadedFile.new(body: "payload", filename: "File file-1.pdf", content_type: "application/pdf")
    end
    built_with = nil
    expected_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:imported])
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

    RecordingStudioAttachable::Dropbox::Integration.stub(:client, lambda { |root:, actor:|
      built_with = [root, actor]
      client
    }) do
      RecordingStudioAttachable::Services::ImportAttachments.stub(:call, expected_result) do
        result = RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.call(
          parent_recording: recording,
          file_ids: ["file-1"],
          actor: :actor
        )

        assert result.success?
      end
    end

    assert_equal [recording, :actor], built_with
  end

  def test_call_rejects_an_oversize_file_before_download
    original_max = RecordingStudioAttachable.configuration.max_file_size
    RecordingStudioAttachable.configuration.max_file_size = 10
    calls = []
    client = Object.new
    client.define_singleton_method(:fetch_file) do |path:|
      calls << [:fetch, path]
      DropboxFakes::DropboxFile.new(
        id: path,
        name: "Huge.pdf",
        path: "/Huge.pdf",
        byte_size: 11
      )
    end
    client.define_singleton_method(:download) do |path:|
      calls << [:download, path]
      DropboxFakes::DownloadedFile.new(body: "payload", filename: "Huge.pdf", content_type: "application/pdf")
    end

    RecordingStudioAttachable::Dropbox::Integration.stub(:client, client) do
      result = RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.call(
        parent_recording: FakeRecording.new(id: "rec-1", recordable_type: "Workspace"),
        file_ids: ["file-1"],
        actor: :actor
      )

      assert result.failure?
      assert_equal "Remote file exceeds maximum file size", result.error
    end

    assert_equal [[:fetch, "file-1"]], calls
  ensure
    RecordingStudioAttachable.configuration.max_file_size = original_max
  end
end
