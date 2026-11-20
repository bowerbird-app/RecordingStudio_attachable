# frozen_string_literal: true

require "test_helper"

class McpCopyTest < Minitest::Test
  def test_tool_names_are_the_three_attachable_actions
    assert_equal %w[create_upload attach import_attachment], RecordingStudioAttachable::McpCopy.tool_names
  end

  def test_register_does_not_raise_when_called
    RecordingStudioAttachable::McpCopy.register!
  end

  def test_named_tools_are_typeless_and_keep_action_names
    source = File.read(File.expand_path("../lib/recording_studio_attachable/mcp_copy.rb", __dir__))

    assert_includes source, "def register!"
    assert_includes source, "return unless defined?(::RecordingStudioMcp)"
    assert_includes source, "name: action.to_s"
    assert_includes source, "action: action"
    refute_includes source, "type:"
    refute_includes source, "RecordingStudioMcp.tool_name"
    refute_includes source, "capability_action"
  end

  def test_inputs_cover_id_type_and_action_fields
    upload = RecordingStudioAttachable::McpCopy.input_for(:create_upload)
    attach = RecordingStudioAttachable::McpCopy.input_for(:attach)
    import = RecordingStudioAttachable::McpCopy.input_for(:import_attachment)

    assert_equal %w[type id filename byte_size checksum content_type], upload.keys
    assert_equal %w[type id signed_blob_id name description caption credit alt_text attachments], attach.keys
    assert_equal %w[type id url name description], import.keys
    assert_equal RecordingStudioAttachable::Api::AttachmentCopy::Fields::TYPE.fetch(:description),
                 upload.fetch("type").fetch(:description)
    assert_equal "Recording id of the parent record.", upload.fetch("id").fetch(:description)
  end

  def test_engine_registers_mcp_copy_after_api
    engine = File.read(File.expand_path("../lib/recording_studio_attachable/engine.rb", __dir__))

    assert_includes engine, 'Engine.initializer "recording_studio_attachable.mcp", after: "recording_studio_attachable.api"'
    assert_includes engine, "RecordingStudioAttachable::McpCopy.register!"
    assert_includes engine, "RecordingStudioMcp::McpController.include ActiveStorage::SetCurrent"
  end
end
