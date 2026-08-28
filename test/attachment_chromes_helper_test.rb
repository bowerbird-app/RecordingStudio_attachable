# frozen_string_literal: true

require "test_helper"
require_relative "../lib/recording_studio_attachable/attachment_chrome"
require_relative "../app/helpers/recording_studio_attachable/attachment_chromes_helper"

module RecordingStudioAttachable
  class AttachmentChromesHelperTest < ActiveSupport::TestCase
    include AttachmentChromesHelper

    FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

    def test_attachment_chrome_frame_dom_id_includes_kind
      recording = FakeRecording.new(id: "abc-123", recordable_type: "Page")

      assert_equal "attachment-chrome-file_button-abc-123",
                   attachment_chrome_frame_dom_id(recording, kind: AttachmentChrome::KIND_FILE_BUTTON)
      assert_equal "attachment-chrome-image_slot-abc-123",
                   attachment_chrome_frame_dom_id(recording, kind: AttachmentChrome::KIND_IMAGE_SLOT)
    end

    def test_attachment_chrome_redirect_params
      assert_equal(
        { redirect_mode: "return_to", return_to: "/attachment_chromes" },
        attachment_chrome_redirect_params(return_to: "/attachment_chromes")
      )
    end

    def test_attachment_chrome_locals_include_round_trip_chrome_params
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
        locals = attachment_chrome_locals(
          recording:,
          return_to: "/attachment_chromes",
          identity: AttachmentChrome.identity_for(
            kind: AttachmentChrome::KIND_IMAGE_SLOT,
            shape: :square,
            size: :"2xl"
          )
        )

        assert_nil locals[:attachment_recording]
        assert_equal AttachmentChrome::KIND_IMAGE_SLOT, locals[:chrome_kind]
        assert_equal :square, locals[:avatar_shape]
        assert_equal :"2xl", locals[:avatar_size]
        assert_equal "Add", locals[:add_label]
        assert_equal "Change", locals[:change_label]
        assert_equal(
          {
            kind: AttachmentChrome::KIND_IMAGE_SLOT,
            shape: :square,
            size: :"2xl",
            add_label: "Add",
            change_label: "Change"
          },
          locals[:chrome_params]
        )
      end
    end

    def test_attachment_chrome_from_params_round_trips_identity
      params = {
        attachment_chrome: {
          kind: "file_button",
          shape: "circle",
          size: "xl",
          add_label: "Add",
          change_label: "Change"
        }
      }

      chrome = AttachmentChrome.from_params(params)

      assert_equal AttachmentChrome::KIND_FILE_BUTTON, chrome[:kind]
      assert_equal :circle, chrome[:shape]
      assert_equal :xl, chrome[:size]
      assert_equal "Add", chrome[:add_label]
      assert_equal "Change", chrome[:change_label]
    end

    def test_attachment_chrome_from_params_rejects_unknown_kind
      assert_nil AttachmentChrome.from_params(attachment_chrome: { kind: "custom_block" })
    end

    def test_render_attachment_image_slot_defaults
      assert_equal :circle, AttachmentChrome::DEFAULT_SHAPE
      assert_equal :xl, AttachmentChrome::DEFAULT_SIZE
    end
  end
end
