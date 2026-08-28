# frozen_string_literal: true

require "test_helper"

module RecordingStudioAttachable
  class AttachmentFileButtonResponsesTest < ActiveSupport::TestCase
    def test_file_button_partial_does_not_emit_turbo_frame
      button_source = File.read(
        File.expand_path("../app/views/recording_studio_attachable/attachment_file_buttons/_button.html.erb", __dir__)
      )
      helper_source = File.read(
        File.expand_path("../app/helpers/recording_studio_attachable/attachment_file_buttons_helper.rb", __dir__)
      )

      assert_includes helper_source, "def render_attachment_file_button(recording, return_to:, target: nil)"
      assert_includes helper_source, "def attachment_preview_url(recording, variant: :square_med)"
      assert_not_includes helper_source, "render_attachment_image_slot"
      assert_not_includes helper_source, "render_parent_attachment"
      assert_includes button_source, "FlatPack::Button::Component.new("
      assert_includes button_source, "text: pick_button_text"
      assert_includes button_source, "turbo_frame: turbo_frame_target"
      assert_no_match(/turbo_frame_tag/, button_source)
      assert_no_match(/attachment_chrome/, button_source)
      assert_not_includes button_source, "FlatPack::Avatar::Component"
    end

    def test_controllers_redirect_see_other_to_return_to_without_turbo_stream_chrome
      attachments_source = File.read(
        File.expand_path("../app/controllers/recording_studio_attachable/attachments_controller.rb", __dir__)
      )
      imports_source = File.read(
        File.expand_path("../app/controllers/recording_studio_attachable/attachment_imports_controller.rb", __dir__)
      )

      assert_includes attachments_source, "status: :see_other"
      assert_includes attachments_source, "AttachmentFileButton.return_to_from"
      assert_not_includes attachments_source, "turbo_stream"
      assert_not_includes attachments_source, "render_attachment_chrome_stream"
      assert_includes imports_source, "status: :see_other"
      assert_includes imports_source, "AttachmentFileButton.return_to_from"
      assert_not_includes imports_source, "turbo_stream"
      assert_not_includes imports_source, "render_attachment_chrome_stream"
    end
  end
end
