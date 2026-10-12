# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"
require_relative "../app/controllers/recording_studio_attachable/application_controller"

class UploadProviderModalEventPageTest < Minitest::Test
  def test_inline_script_emits_payload_as_a_javascript_object_literal
    payload = {
      namespace: "recording-studio-attachable",
      type: "provider-auth-complete",
      providerKey: "google_drive",
      modalId: "modal-1",
      redirectPath: "/google_drive/recordings/rec-1/imports"
    }
    html = RecordingStudioAttachable::ApplicationController.new.send(
      :upload_provider_modal_event_page,
      payload_json: ERB::Util.json_escape(payload.to_json),
      close_window: true
    )

    script = html[%r{<script>(.*?)</script>}m, 1]
    refute_nil script, "expected an inline script on the modal event page"

    payload_line = script.lines.map(&:strip).find { |line| line.start_with?("const payload =") }
    refute_nil payload_line, "expected a const payload assignment"
    refute_match(/\Aconst payload = JSON\.parse\("/, payload_line)
    assert_match(/\Aconst payload = \{.*\};\z/, payload_line)

    literal = payload_line.delete_prefix("const payload = ").delete_suffix(";")
    parsed = JSON.parse(literal)
    assert_equal "provider-auth-complete", parsed.fetch("type")
    assert_equal "google_drive", parsed.fetch("providerKey")
    assert_equal "modal-1", parsed.fetch("modalId")

    check_rendered_script_with_node(script) if node_available?
  end

  private

  def node_available?
    system("node", "-v", out: File::NULL, err: File::NULL)
  end

  def check_rendered_script_with_node(script)
    Dir.mktmpdir("upload-provider-modal-event-page") do |dir|
      path = File.join(dir, "modal_event_page.js")
      File.write(path, script)
      stdout, stderr, status = Open3.capture3("node", "--check", path)
      assert status.success?, "node --check rejected the rendered popup script: #{stderr}\n#{stdout}\n#{script}"
    end
  end
end
