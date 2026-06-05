# frozen_string_literal: true

require "test_helper"
require_relative "dummy/config/environment"

class DummyRecordingStudioIntegrationTest < ActiveSupport::TestCase
  def test_dummy_app_recordables_have_recording_studio_3_hierarchy_declarations
    assert RecordingStudio.validate_recordable_declarations!

    assert RecordingStudio.root_allowed?("Workspace")
    assert_equal [], RecordingStudio.declared_allowed_parent_types_for("Workspace")

    assert_not RecordingStudio.root_allowed?("Page")
    assert_equal ["Workspace"], RecordingStudio.declared_allowed_parent_types_for("Page")

    assert_not RecordingStudio.root_allowed?("ChatThread")
    assert_equal ["Workspace"], RecordingStudio.declared_allowed_parent_types_for("ChatThread")

    assert_not RecordingStudio.root_allowed?("ChatMessage")
    assert_equal ["ChatThread"], RecordingStudio.declared_allowed_parent_types_for("ChatMessage")

    assert_not RecordingStudio.root_allowed?("RecordingStudioAttachable::Attachment")
    assert_equal [], RecordingStudio.declared_allowed_parent_types_for("RecordingStudioAttachable::Attachment")
  end

  def test_dummy_app_attachable_capability_registers_attachment_as_capability_child
    registration = RecordingStudio.registered_capabilities.fetch(:attachable)

    assert_equal RecordingStudio::Capabilities::Attachable::RecordingMethods, registration.fetch(:recording_methods)
    assert_equal "recording_studio_attachable", registration.fetch(:source)
    assert_equal ["RecordingStudioAttachable::Attachment"], registration.fetch(:child_recordables)
    assert_equal ["RecordingStudioAttachable::Attachment"], RecordingStudio.capability_child_recordables_for(:attachable)
    assert_equal %w[Page Workspace], RecordingStudio.allowed_parent_types_for("RecordingStudioAttachable::Attachment")
  end

  def test_dummy_app_attachable_capability_options_are_available_for_parent_types
    assert_equal(
      {
        allowed_content_types: ["image/*", "application/pdf", "text/plain"],
        max_file_size: 25.megabytes,
        enabled_attachment_kinds: %i[image file]
      },
      RecordingStudio.capability_options(:attachable, for: "Workspace").slice(
        :allowed_content_types,
        :max_file_size,
        :enabled_attachment_kinds
      )
    )
    assert_equal ["image/*"], RecordingStudio.capability_options(:attachable, for: "Page")[:allowed_content_types]
    assert_equal %i[image], RecordingStudio.capability_options(:attachable, for: "Page")[:enabled_attachment_kinds]
  end
end
