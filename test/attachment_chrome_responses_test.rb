# frozen_string_literal: true

require "test_helper"

module RecordingStudioAttachable
  class AttachmentChromeResponsesTest < ActiveSupport::TestCase
    def test_render_attachment_chrome_stream_replaces_frame_not_bare_chrome
      source = File.read(File.expand_path("../lib/recording_studio_attachable/attachment_chrome_responses.rb", __dir__))

      assert_includes source, "AttachmentChrome.frame_dom_id(recording, kind: chrome.fetch(:kind))"
      assert_includes source, 'partial: "recording_studio_attachable/attachment_chromes/frame"'
      assert_includes source, "stream_locals_for(recording, return_to, chrome)"
      assert_no_match(%r{partial:\s*"recording_studio_attachable/attachment_chromes/chrome"}, source)
    end

    def test_attachment_chrome_frame_partial_wraps_chrome_in_matching_turbo_frame
      frame_source = File.read(
        File.expand_path("../app/views/recording_studio_attachable/attachment_chromes/_frame.html.erb", __dir__)
      )
      chrome_source = File.read(
        File.expand_path("../app/views/recording_studio_attachable/attachment_chromes/_chrome.html.erb", __dir__)
      )

      assert_includes frame_source, "turbo_frame_tag attachment_chrome_frame_dom_id(recording, kind:)"
      assert_includes frame_source, 'render "recording_studio_attachable/attachment_chromes/chrome"'
      assert_includes chrome_source, 'hidden_field_tag "attachment_chrome[#{key}]"'
      assert_includes chrome_source, "chrome_params.each"
      assert_no_match(/turbo_frame_tag/, chrome_source)
    end

    def test_controllers_stream_attachment_chrome_with_round_tripped_identity
      attachments_source = File.read(
        File.expand_path("../app/controllers/recording_studio_attachable/attachments_controller.rb", __dir__)
      )
      imports_source = File.read(
        File.expand_path("../app/controllers/recording_studio_attachable/attachment_imports_controller.rb", __dir__)
      )

      assert_includes attachments_source, "attachment_chrome_from_params"
      assert_includes attachments_source, "render_attachment_chrome_stream"
      assert_includes attachments_source, "chrome.present?"
      assert_includes imports_source, "attachment_chrome_from_params"
      assert_includes imports_source, "render_attachment_chrome_stream"
      assert_includes imports_source, "chrome.present?"
    end

    def test_chrome_markup_posts_identity_fields_for_round_trip
      chrome_source = File.read(
        File.expand_path("../app/views/recording_studio_attachable/attachment_chromes/_chrome.html.erb", __dir__)
      )

      assert_includes chrome_source, 'hidden_field_tag "attachment_chrome[#{key}]"'
      assert_includes chrome_source, "KIND_IMAGE_SLOT"
      assert_includes chrome_source, "FlatPack::Avatar::Component.new("
      assert_includes chrome_source, "text: pick_button_text"
      assert_not_includes chrome_source, 'icon: "camera"'
      assert_not_includes chrome_source, "icon_only: true"
    end
  end
end
