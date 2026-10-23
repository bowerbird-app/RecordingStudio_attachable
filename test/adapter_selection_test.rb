# frozen_string_literal: true

require "test_helper"

class AdapterSelectionTest < Minitest::Test
  def test_value_reads_string_or_symbol_keys
    assert_equal "file-1", RecordingStudioAttachable::Adapter::Selection.value({ "id" => "file-1" }, :id)
    assert_equal "file-2", RecordingStudioAttachable::Adapter::Selection.value({ id: "file-2" }, :id)
  end

  def test_files_normalizes_strings_and_hashes
    files = RecordingStudioAttachable::Adapter::Selection.files(
      ["", "file-1", { id: "file-2", resourceKey: "rk", name: "Brief" }, { "id" => "" }],
      extra_keys: { "resource_key" => %i[resource_key resourceKey] }
    )

    assert_equal(
      [
        { "id" => "file-1" },
        { "id" => "file-2", "resource_key" => "rk", "name" => "Brief", "metadata" => {} }
      ],
      files
    )
  end

  def test_from_attachments_drops_provider_metadata
    payload = RecordingStudioAttachable::Adapter::Selection.from_attachments(
      [
        {
          provider_payload: { "id" => "file-1" },
          name: "Brief",
          description: "Notes",
          metadata: { "provider" => "extra_cloud", "folder" => "inbox" }
        }
      ]
    ).first

    assert_equal "file-1", payload.fetch("id")
    assert_equal "Brief", payload.fetch("name")
    assert_equal "Notes", payload.fetch("description")
    assert_equal({ "folder" => "inbox" }, payload.fetch("metadata"))
  end
end
