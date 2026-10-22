# frozen_string_literal: true

require "test_helper"
require_relative "google_drive_fakes"

class GoogleDriveEngineTest < Minitest::Test
  def test_remote_importer_imports_ids_without_session_tokens
    captured = nil

    RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.stub(:call, lambda { |**kwargs|
      captured = kwargs
      :imported
    }) do
      result = RecordingStudioAttachable::GoogleDrive::Engine.send(
        :remote_importer,
        parent_recording: :recording,
        attachments: [
          {
            provider_payload: { "id" => "file-1", "resource_key" => "rk-1" },
            name: "Brief",
            description: "Notes",
            metadata: { "provider" => "google_drive", "folder" => "inbox" }
          }
        ],
        actor: :actor,
        impersonator: :impersonator,
        context: Object.new
      )

      assert_equal :imported, result
    end

    selection = captured[:file_ids].first
    assert_equal :recording, captured[:parent_recording]
    assert_nil captured[:access_token]
    assert_equal :actor, captured[:actor]
    assert_equal :impersonator, captured[:impersonator]
    assert_equal "file-1", selection.fetch("id")
    assert_equal "rk-1", selection.fetch("resource_key")
    assert_equal "Brief", selection.fetch("name")
    assert_equal "Notes", selection.fetch("description")
    assert_equal({ "folder" => "inbox" }, selection.fetch("metadata"))
  end
end
