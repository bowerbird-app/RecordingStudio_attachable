# frozen_string_literal: true

require "test_helper"

class ClientPickerTest < Minitest::Test
  def test_provider_options_build_a_client_picker_registration
    importer = ->(*) { :imported }

    options = RecordingStudioAttachable::Adapter::ClientPicker.provider_options(
      label: "My Cloud",
      launcher: "my_cloud",
      launcher_module: "my_cloud/picker_launcher",
      remote_importer: importer,
      allowed_payload_keys: %w[id],
      bootstrap_path: "/my_cloud/bootstrap",
      import_path: "/my_cloud/imports"
    )

    assert_equal "My Cloud", options[:label]
    assert_equal "cloud", options[:icon]
    assert_equal :client_picker, options[:strategy]
    assert_equal "my_cloud", options[:launcher]
    assert_equal "my_cloud/picker_launcher", options[:launcher_module]
    assert_equal importer, options[:remote_importer]
    assert_equal %w[id], options[:allowed_payload_keys]
    assert_equal "/my_cloud/bootstrap", options[:url]
    assert_equal "/my_cloud/bootstrap", options[:bootstrap_url]
    assert_equal "/my_cloud/imports", options[:import_url]
  end
end
