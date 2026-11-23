# frozen_string_literal: true

require "test_helper"

class McpCopyTest < Minitest::Test
  def test_tool_names_are_the_three_attachable_actions
    assert_equal %w[create_upload attach import_attachment], RecordingStudioAttachable::McpCopy.tool_names
  end

  def test_register_does_not_raise_when_called
    RecordingStudioAttachable::McpCopy.register!
  end

  def test_openapi_is_the_attachment_actions_specs
    openapi = RecordingStudioAttachable::McpCopy::OPENAPI

    assert_equal RecordingStudioAttachable::Api::AttachmentActions::CREATE_UPLOAD_OPENAPI, openapi.fetch(:create_upload)
    assert_equal RecordingStudioAttachable::Api::AttachmentActions::ATTACH_OPENAPI, openapi.fetch(:attach)
    assert_equal RecordingStudioAttachable::Api::AttachmentActions::IMPORT_ATTACHMENT_OPENAPI,
                 openapi.fetch(:import_attachment)
    RecordingStudioAttachable::McpCopy::ACTIONS.each do |action|
      spec = openapi.fetch(action)

      assert spec.fetch(:title).present?
      assert spec.fetch(:description).present?
      assert spec.dig(:responses, "200", :description).present?
      refute_match(/\bconfig\./, spec.fetch(:description))
      refute_match(/\bAccess\b/, spec.fetch(:description))
    end
  end

  def test_protocol_input_uses_the_type_field_description
    description = "Public type of the parent record. Call describe if you do not know it."
    fields = RecordingStudioAttachable::Api::AttachmentCopy::Fields

    assert_equal description, fields::TYPE.fetch(:description)
    assert_equal description, fields::CREATE_UPLOAD.fetch(:type).fetch(:description)
    assert_equal description, fields::ATTACH.fetch(:type).fetch(:description)
    assert_equal description, fields::IMPORT.fetch(:type).fetch(:description)
    assert_equal description, RecordingStudioAttachable::McpCopy::TYPE_INPUT.fetch(:description)
    refute RecordingStudioAttachable::McpCopy::TYPE_INPUT.key?(:required)
    refute RecordingStudioAttachable::McpCopy::ID_INPUT.key?(:required)
  end
end
