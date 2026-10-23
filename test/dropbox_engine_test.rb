# frozen_string_literal: true

require "test_helper"
require_relative "dropbox_fakes"

class DropboxEngineTest < Minitest::Test
  def test_remote_importer_imports_ids_without_session_tokens
    captured = nil

    RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.stub(:call, lambda { |**kwargs|
      captured = kwargs
      :imported
    }) do
      result = RecordingStudioAttachable::Dropbox::Engine.send(
        :remote_importer,
        parent_recording: :recording,
        attachments: [
          {
            provider_payload: { "id" => "file-1" },
            name: "Brief",
            description: "Notes",
            metadata: { "provider" => "dropbox", "folder" => "inbox" }
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
    assert_equal "Brief", selection.fetch("name")
    assert_equal "Notes", selection.fetch("description")
    assert_equal({ "folder" => "inbox" }, selection.fetch("metadata"))
  end
end
