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
    assert_includes text, "use file"
    assert_includes text, "use url"
    assert_includes text, "data plus filename"
  end

  def test_upload_source_fields_and_the_chatgpt_file_object
    original = RecordingStudioAttachable.configuration.inline_upload_max_bytes
    RecordingStudioAttachable.configuration.inline_upload_max_bytes = 2.megabytes
    fields = RecordingStudioAttachable::McpCopy.upload_source_fields

    assert_equal %w[url data filename], fields.keys
    url = fields.fetch("url")
    data = fields.fetch("data")
    filename = fields.fetch("filename")
    assert_equal "string", url.fetch("type")
    assert_equal "string", data.fetch("type")
    assert_equal "string", filename.fetch("type")
    assert_includes url.fetch("description"), "public https://"
    assert_includes url.fetch("description"), "Never put a local path in url"
    assert_includes url.fetch("description"), "send file"
    assert_includes data.fetch("description"), "base64"
    assert_includes data.fetch("description"), "filename"
    assert_includes data.fetch("description"), "send file"
    assert_includes data.fetch("description"), "2 MB"
    refute_includes data.fetch("description"), "inline_upload_max_bytes"
    assert_includes filename.fetch("description"), "cover.jpg"

    contract = RecordingStudioAttachable::Api::AttachmentContracts.create_upload.fetch(:fields)
    assert_equal url.fetch("description"), contract.dig(:url, :description)
    assert_equal data.fetch("description"), contract.dig(:data, :description)
    assert_equal filename.fetch("description"), contract.dig(:filename, :description)

    RecordingStudioAttachable.configuration.inline_upload_max_bytes = 1.megabyte
    tighter = RecordingStudioAttachable::McpCopy.upload_source_fields.fetch("data").fetch("description")
    assert_includes tighter, "1 MB"
    refute_includes tighter, "2 MB"

    schema = RecordingStudioAttachable::McpCopy.upload_file_field
    assert_equal "object", schema.fetch("type")
    assert_equal %w[download_url file_id], schema.fetch("required")
    assert_equal ["file"], RecordingStudioAttachable::McpCopy::FILE_PARAMS
    assert_equal "openai/fileParams", RecordingStudioAttachable::McpCopy::FILE_PARAMS_KEY
    %w[download_url file_id mime_type file_name].each do |key|
      property = schema.fetch("properties").fetch(key)
      assert_equal "string", property.fetch("type")
      assert property.fetch("description").present?, key
    end
    assert_equal :hash, contract.dig(:file, :type)
    assert_equal false, contract.dig(:file, :required)
    assert_equal schema.fetch("description"), contract.dig(:file, :description)
    assert_equal schema.fetch("properties"), contract.dig(:file, :properties)

    rights = RecordingStudioAttachable::McpCopy.rights_confirmed_field
    assert_equal "boolean", rights.fetch("type")
    assert_includes rights.fetch("description"), RecordingStudioAttachable::UploadRights::QUESTION
    assert_equal rights.fetch("description"), contract.dig(:rights_confirmed, :description)
    import = RecordingStudioAttachable::Api::AttachmentContracts.import_attachment.fetch(:fields)
    assert_equal rights.fetch("description"), import.dig(:rights_confirmed, :description)
  ensure
    RecordingStudioAttachable.configuration.inline_upload_max_bytes = original
  end

  def test_import_description_does_not_call_a_single_file_parent_a_cover
    copy = RecordingStudioAttachable::Api::AttachmentCopy::Text::IMPORT
    names = { create_upload: "workspace_create_upload", attach: "workspace_attach", import_attachment: "workspace_import_attachment" }
    import_text = RecordingStudioAttachable::McpCopy::Text.for(:import_attachment, names: names, limits: "Limits.")
    attach_text = RecordingStudioAttachable::McpCopy::Text.for(:attach, names: names, limits: "Limits.")

    refute_includes copy, "such as a cover"
    refute_includes import_text, "such as a cover"
    assert_includes attach_text, "such as a cover"
  end

  def test_contract_fields_do_not_take_a_type
    fields = RecordingStudioAttachable::Api::AttachmentCopy::Fields

    refute fields::CREATE_UPLOAD.key?(:type)
    refute fields::ATTACH.key?(:type)
    refute fields::IMPORT.key?(:type)
    refute RecordingStudioAttachable::McpCopy::ID_INPUT.key?(:required)
  end
end
