# frozen_string_literal: true

require "test_helper"

class DropboxEngineTest < Minitest::Test
  FakeContext = Struct.new(:session)

  def test_remote_importer_resolves_session_token_and_imports_ids
    captured = nil
    context = FakeContext.new({ "recording_studio_attachable_dropbox" => { "tokens" => { "access_token" => "tok" } } })

    RecordingStudioAttachable::Dropbox::SessionAccessToken.stub(:fetch, "tok") do
      RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.stub(:call, lambda { |**kwargs|
        captured = kwargs
        :imported
      }) do
        result = RecordingStudioAttachable::Dropbox::Engine.send(
          :remote_importer,
          parent_recording: :recording,
          attachments: [
            { provider_payload: { "id" => "file-1" }, name: "Brief", description: nil, metadata: { "provider" => "dropbox" } }
          ],
          actor: :actor,
          impersonator: :impersonator,
          context: context
        )

        assert_equal :imported, result
      end
    end

    assert_equal :recording, captured[:parent_recording]
    assert_equal "tok", captured[:access_token]
    assert_equal :actor, captured[:actor]
    assert_equal :impersonator, captured[:impersonator]
    assert_equal "file-1", captured[:file_ids].first.fetch("id")
    assert_equal "Brief", captured[:file_ids].first.fetch("name")
    assert_not captured[:file_ids].first.key?("metadata")
  end

  def test_remote_importer_keeps_description_and_non_provider_metadata
    captured = nil
    context = FakeContext.new({})

    RecordingStudioAttachable::Dropbox::SessionAccessToken.stub(:fetch, "tok") do
      RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.stub(:call, lambda { |**kwargs|
        captured = kwargs
        :imported
      }) do
        RecordingStudioAttachable::Dropbox::Engine.send(
          :remote_importer,
          parent_recording: :recording,
          attachments: [
            {
              provider_payload: { id: "file-2" },
              name: "Sheet",
              description: "Quarterly",
              metadata: { "provider" => "dropbox", "folder" => "finance" }
            }
          ],
          context: context
        )
      end
    end

    selection = captured[:file_ids].first
    assert_equal "file-2", selection.fetch("id")
    assert_equal "Sheet", selection.fetch("name")
    assert_equal "Quarterly", selection.fetch("description")
    assert_equal({ "folder" => "finance" }, selection.fetch("metadata"))
  end
end
