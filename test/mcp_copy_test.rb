# frozen_string_literal: true

require "test_helper"

class McpCopyTest < Minitest::Test
  def test_actions_are_the_three_attachable_writes
    assert_equal %i[create_upload attach import_attachment], RecordingStudioAttachable::McpCopy::ACTIONS
  end

  def test_tool_names_follow_attachable_types
    names = RecordingStudioAttachable::McpCopy.tool_names

    assert_instance_of Array, names
    refute_includes names, "create_upload"
    refute_includes names, "attach"
    refute_includes names, "import_attachment"
    names.each do |name|
      assert_match(/\A[a-z0-9_]+_(create_upload|attach|import_attachment)\z/, name)
    end
  end

  def test_register_does_not_raise_when_called
    RecordingStudioAttachable::McpCopy.register!
  end

  def test_upload_text_tells_a_client_that_cannot_put_to_send_url_or_data
    text = RecordingStudioAttachable::McpCopy::Text.for(
      :create_upload,
      names: { create_upload: "workspace_create_upload", attach: "workspace_attach" },
      limits: "Limits."
    )

    assert_includes text, "If you cannot PUT the bytes"
    assert_includes text, "url"
    assert_includes text, "data and filename"
  end

  def test_import_description_does_not_call_a_single_file_parent_a_cover
    copy = RecordingStudioAttachable::Api::AttachmentCopy::Text::IMPORT

    refute_includes copy, "such as a cover"
  end

  def test_contract_fields_do_not_take_a_type
    fields = RecordingStudioAttachable::Api::AttachmentCopy::Fields

    refute fields::CREATE_UPLOAD.key?(:type)
    refute fields::ATTACH.key?(:type)
    refute fields::IMPORT.key?(:type)
    refute RecordingStudioAttachable::McpCopy::ID_INPUT.key?(:required)
  end
end
