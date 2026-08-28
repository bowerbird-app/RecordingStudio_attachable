# frozen_string_literal: true

require "test_helper"
require_relative "../lib/recording_studio_attachable/parent_attachment_slot"
require_relative "../app/helpers/recording_studio_attachable/parent_attachments_helper"

module RecordingStudioAttachable
  class ParentAttachmentsHelperTest < ActiveSupport::TestCase
    include ParentAttachmentsHelper

    FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

    def test_parent_attachment_frame_dom_id
      recording = FakeRecording.new(id: "abc-123", recordable_type: "User")

      assert_equal "parent-attachment-abc-123", parent_attachment_frame_dom_id(recording)
    end

    def test_parent_attachment_redirect_params
      assert_equal(
        { redirect_mode: "return_to", return_to: "/users/1" },
        parent_attachment_redirect_params(return_to: "/users/1")
      )
    end

    def test_parent_attachment_slot_locals_use_image_specific_copy_for_image_only_parents
      recording = FakeRecording.new(id: "parent-1", recordable_type: "User")
      relation = Object.new
      relation.define_singleton_method(:first) { nil }

      recording.define_singleton_method(:attachments) { |**| relation }

      RecordingStudio.stub(:capability_options, {
                             allowed_content_types: ["image/*"],
                             enabled_attachment_kinds: [:image],
                             max_file_size: 25.megabytes,
                             image_processing_enabled: true,
                             image_processing_max_width: 1200,
                             image_processing_max_height: 1200,
                             image_processing_quality: 0.75
                           }) do
        locals = parent_attachment_slot_locals(recording:, return_to: "/users/1")

        assert_nil locals[:attachment_recording]
        assert_equal :circle, locals[:avatar_shape]
        assert_equal :xl, locals[:avatar_size]
        assert_equal "Change", locals[:replace_button_text]
        assert_equal "Add", locals[:add_button_text]
      end
    end

    def test_render_parent_attachment_passes_shape_and_size_to_frame_locals
      recording = FakeRecording.new(id: "parent-1", recordable_type: "User")

      assert_equal :circle, ParentAttachmentSlot::DEFAULT_SHAPE
      assert_equal :xl, ParentAttachmentSlot::DEFAULT_SIZE

      locals = parent_attachment_slot_locals(recording:, return_to: "/users/1", shape: :square, size: :lg)

      assert_equal :square, locals[:avatar_shape]
      assert_equal :lg, locals[:avatar_size]
    end
  end
end
