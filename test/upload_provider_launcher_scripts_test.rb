# frozen_string_literal: true

require "test_helper"
require "action_view"
require "action_controller"

class UploadProviderLauncherScriptsTest < Minitest::Test
  LAUNCHER_TAG = 'javascript_tag(%(import #{module_path.to_json}), type: "module", nonce: true)'
  LAUNCHER_MODULE = "controllers/recording_studio_attachable/google_drive_picker_launcher"
  VIEW_PATHS = [
    File.expand_path("../app/views/recording_studio_attachable/attachment_uploads/_uploader.html.erb", __dir__),
    File.expand_path("../app/views/recording_studio_attachable/attachment_image_pickers/_modal.html.erb", __dir__)
  ].freeze

  def test_upload_and_picker_views_emit_unescaped_launcher_imports
    VIEW_PATHS.each do |path|
      source = File.read(path)
      assert_includes source, LAUNCHER_TAG, "#{path} must use the string-argument javascript_tag form"

      html = launcher_view.render(
        inline: "<%= #{LAUNCHER_TAG} %>",
        locals: { module_path: LAUNCHER_MODULE }
      )

      assert_includes html, %(import "#{LAUNCHER_MODULE}")
      assert_includes html, 'type="module"'
      refute_includes html, "&quot;", "#{path} launcher script must not HTML-escape import quotes"
    end
  end

  private

  def launcher_view
    @launcher_view ||= Class.new(ActionView::Base) do
      def content_security_policy_nonce
        "test-nonce"
      end
    end.with_empty_template_cache.with_view_paths([])
  end
end
