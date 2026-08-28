# frozen_string_literal: true

require "test_helper"

module RecordingStudioAttachable
  class ParentAttachmentResponsesTest < ActiveSupport::TestCase
    def test_render_parent_attachment_slot_stream_replaces_turbo_frame_not_bare_slot
      source = File.read(File.expand_path("../lib/recording_studio_attachable/parent_attachment_responses.rb", __dir__))

      assert_includes source, "ParentAttachmentSlot.frame_dom_id(recording)"
      assert_includes source, 'partial: "recording_studio_attachable/parent_attachments/frame"'
      assert_no_match(%r{partial:\s*"recording_studio_attachable/parent_attachments/slot"}, source)
    end

    def test_parent_attachment_frame_partial_wraps_slot_in_matching_turbo_frame
      frame_source = File.read(
        File.expand_path("../app/views/recording_studio_attachable/parent_attachments/_frame.html.erb", __dir__)
      )
      slot_source = File.read(
        File.expand_path("../app/views/recording_studio_attachable/parent_attachments/_slot.html.erb", __dir__)
      )

      assert_includes frame_source, "turbo_frame_tag parent_attachment_frame_dom_id(recording)"
      assert_includes frame_source, 'render "recording_studio_attachable/parent_attachments/slot"'
      assert_includes slot_source, 'id="parent-attachment-slot"'
      assert_no_match(/turbo_frame_tag/, slot_source)
    end

    def test_replace_and_import_controllers_stream_parent_attachment_frame
      attachments_source = File.read(
        File.expand_path("../app/controllers/recording_studio_attachable/attachments_controller.rb", __dir__)
      )
      imports_source = File.read(
        File.expand_path("../app/controllers/recording_studio_attachable/attachment_imports_controller.rb", __dir__)
      )

      assert_includes attachments_source, "render_parent_attachment_slot_stream"
      assert_includes imports_source, "render_parent_attachment_slot_stream"
      assert_no_match(%r{parent_attachments/slot"}, attachments_source)
      assert_no_match(%r{parent_attachments/slot"}, imports_source)
    end
  end
end
