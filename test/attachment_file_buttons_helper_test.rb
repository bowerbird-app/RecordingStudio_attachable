# frozen_string_literal: true

require "test_helper"
require_relative "../lib/recording_studio_attachable/attachment_file_button"
require_relative "../app/helpers/recording_studio_attachable/attachment_file_buttons_helper"

module RecordingStudioAttachable
  class AttachmentFileButtonsHelperTest < ActiveSupport::TestCase
    include AttachmentFileButtonsHelper

    FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

    def test_attachment_file_button_locals_include_redirect_and_optional_target
      recording = FakeRecording.new(id: "parent-1", recordable_type: "Page")
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
        locals = AttachmentFileButton.locals(
          recording:,
          return_to: "/attachment_chromes",
          target: "page-avatar-attachment"
        )

        assert_nil locals[:attachment_recording]
        assert_equal "page-avatar-attachment", locals[:turbo_frame_target]
        assert_equal "Add", locals[:add_label]
        assert_equal "Change", locals[:change_label]
        assert_equal(
          { redirect_mode: "return_to", return_to: "/attachment_chromes" },
          locals[:redirect_params]
        )
      end
    end

    def test_attachment_preview_url_uses_authorized_preview_for_first_attachment
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Page")
      attachment_recording = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment")
      relation = Object.new
      relation.define_singleton_method(:first) { attachment_recording }
      parent.define_singleton_method(:attachments) { |**| relation }

      define_singleton_method(:authorized_attachment_preview_path) do |recording, variant|
        "/previews/#{recording.id}/#{variant}"
      end

      assert_equal "/previews/att-1/square_med", attachment_preview_url(parent)
      assert_equal "/previews/att-1/large", attachment_preview_url(parent, variant: :large)
    end

    def test_attachment_preview_url_returns_nil_when_empty
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Page")
      relation = Object.new
      relation.define_singleton_method(:first) { nil }
      parent.define_singleton_method(:attachments) { |**| relation }

      assert_nil attachment_preview_url(parent)
    end
  end
end
