# frozen_string_literal: true

require "test_helper"
require_relative "../lib/recording_studio_attachable/attachment_file_button"

module RecordingStudioAttachable
  class UploadPresentationTest < Minitest::Test
    FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

    def setup
      @original = RecordingStudioAttachable.configuration.upload_presentation
    end

    def teardown
      RecordingStudioAttachable.configuration.upload_presentation = @original
    end

    def test_configuration_defaults_to_page
      configuration = Configuration.new

      assert_equal :page, configuration.upload_presentation
      assert_equal :page, configuration.to_h[:upload_presentation]
    end

    def test_configuration_normalizes_strings_and_blank_values
      configuration = Configuration.new
      configuration.upload_presentation = " Modal "

      assert_equal :modal, configuration.upload_presentation

      configuration.upload_presentation = nil

      assert_equal :page, configuration.upload_presentation
    end

    def test_configuration_merge_sets_upload_presentation
      configuration = Configuration.new
      configuration.merge!(upload_presentation: "modal")

      assert_equal :modal, configuration.upload_presentation
    end

    def test_configuration_rejects_unknown_presentations
      error = assert_raises(ArgumentError) { Configuration.new.upload_presentation = :drawer }

      assert_includes error.message, ":page or :modal"
    end

    def test_presentation_for_falls_back_to_global_configuration
      assert_equal :page, AttachmentFileButton.presentation_for(nil)

      RecordingStudioAttachable.configuration.upload_presentation = :modal

      assert_equal :modal, AttachmentFileButton.presentation_for(nil)
      assert_equal :page, AttachmentFileButton.presentation_for(:page)
      assert_equal :modal, AttachmentFileButton.presentation_for("modal")
      assert_raises(ArgumentError) { AttachmentFileButton.presentation_for(:sheet) }
    end

    def test_locals_carry_the_resolved_presentation
      recording = empty_recording

      RecordingStudio.stub(:capability_options, {}) do
        assert_equal :page, AttachmentFileButton.locals(recording:, return_to: "/back")[:presentation]
        assert_equal :modal, AttachmentFileButton.locals(recording:, return_to: "/back", presentation: :modal)[:presentation]
      end
    end

    def test_upload_modal_ids_and_params
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Page")

      assert_equal "attachable-upload-modal-rec-1", AttachmentFileButton.upload_modal_id(recording)
      assert_equal "attachable-upload-modal-rec-1-frame", AttachmentFileButton.upload_modal_frame_id(recording)
      assert_equal(
        {
          redirect_mode: "return_to",
          return_to: "/back",
          embed: "upload_modal",
          frame_id: "attachable-upload-modal-rec-1-frame"
        },
        AttachmentFileButton.upload_modal_params(recording, return_to: "/back")
      )
    end

    def test_upload_modal_params_skip_blank_return_to
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Page")
      params = AttachmentFileButton.upload_modal_params(recording, return_to: nil)

      assert_not params.key?(:return_to)
      assert_equal "upload_modal", params[:embed]
    end

    def test_page_and_modal_share_one_uploader_template
      page = File.read(File.expand_path("../app/views/recording_studio_attachable/attachment_uploads/new.html.erb", __dir__))
      uploader = File.read(File.expand_path("../app/views/recording_studio_attachable/attachment_uploads/_uploader.html.erb", __dir__))
      script = File.read(File.expand_path("../app/javascript/controllers/recording_studio_attachable/upload_controller.js", __dir__))

      assert_includes page, 'render "recording_studio_attachable/attachment_uploads/uploader", modal: true'
      assert_includes page, 'render "recording_studio_attachable/attachment_uploads/uploader", modal: false'
      assert_includes uploader, 'type="file" multiple'
      assert_includes uploader, 'data-recording-studio-attachable--upload-target="dropzone"'
      assert_includes uploader, 'data-recording-studio-attachable--upload-target="progressTemplate"'
      assert_includes uploader, 'success-behavior-value="<%= embedded ? "event" : "redirect" %>"'
      assert_includes uploader, "upload_providers.reject(&:modal?)"
      assert_includes script, 'new CustomEvent("attachable:uploaded"'
      assert_includes script, 'successBehavior: { type: String, default: "redirect" }'
    end

    private

    def empty_recording
      recording = FakeRecording.new(id: "parent-1", recordable_type: "Page")
      relation = Object.new
      relation.define_singleton_method(:first) { nil }
      recording.define_singleton_method(:attachments) { |**| relation }
      recording
    end
  end
end
