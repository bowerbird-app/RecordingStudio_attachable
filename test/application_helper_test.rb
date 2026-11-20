# frozen_string_literal: true

require "test_helper"
require_relative "../app/helpers/recording_studio_attachable/application_helper"

class ApplicationHelperTest < Minitest::Test
  class Host
    include RecordingStudioAttachable::ApplicationHelper

    def t(key, **)
      I18n.t(key)
    end
  end

  class HostRoutes
    def attachment_path(recording, **)
      "/host/attachments/#{recording}"
    end

    def recording_attachment_imports_path(recording, **)
      "/host/recordings/#{recording}/imports"
    end

    def recording_attachment_upload_path(recording, **)
      "/host/recordings/#{recording}/upload"
    end

    def attachment_file_path(recording)
      "/host/attachments/#{recording}/file"
    end

    def attachment_preview_file_path(recording, variant_name:)
      "/host/attachments/#{recording}/preview/#{variant_name}"
    end
  end

  class RoutedHost < Host
    def recording_studio_attachable
      HostRoutes.new
    end
  end

  def setup
    load_engine_routes!
    @helper = Host.new
    @routed = RoutedHost.new
  end

  def load_engine_routes!
    helpers = RecordingStudioAttachable::Engine.routes.url_helpers
    return if helpers.respond_to?(:attachment_preview_file_path)

    load File.expand_path("../config/routes.rb", __dir__)
  end

  def test_preview_path_returns_nil_without_a_usable_preview
    assert_nil @helper.authorized_attachment_preview_path(nil, :med)

    blank = recording(nil)
    assert_nil @helper.authorized_attachment_preview_path(blank, :med)

    plain = recording(Object.new)
    assert_nil @helper.authorized_attachment_preview_path(plain, :med)

    empty = recording(preview_attachment(nil))
    assert_nil @helper.authorized_attachment_preview_path(empty, :med)
  end

  def test_preview_path_uses_the_engine_route_until_the_attachment_builds_a_delivery_url
    rails_only = recording(preview_attachment(:ready))
    rails_path = @helper.authorized_attachment_preview_path(rails_only, :large)

    assert_includes rails_path, "/preview/large"

    routed = @routed.authorized_attachment_preview_path(rails_only, :large)
    assert_equal "/host/attachments/#{rails_only}/preview/large", routed

    direct = recording(preview_attachment(:ready, variant_url: "https://images.example.test/med"))
    assert_equal(
      "https://images.example.test/med",
      @helper.authorized_attachment_preview_path(direct, :med)
    )
  end

  def test_file_path_stays_on_the_engine_route_until_the_attachment_builds_one
    plain = Object.new
    plain.define_singleton_method(:to_param) { "att-9" }
    rails_path = @helper.authorized_attachment_file_path(plain)

    assert_includes rails_path, "att-9"

    attachment = Object.new
    attachment.define_singleton_method(:original_url) { |rails_url:| "https://images.example.test/#{rails_url}" }
    record = recording(attachment)
    direct = @helper.authorized_attachment_file_path(record)
    assert_includes direct, "https://images.example.test/"
    assert_includes direct, "att-1"

    routed = @routed.authorized_attachment_file_path(record)
    assert_includes routed, "https://images.example.test/"
    assert_includes routed, "/host/attachments/#{record}/file"
  end

  def test_route_wrappers_delegate_to_the_host_engine_when_it_is_mounted
    assert_equal "/host/attachments/att-1", @routed.attachable_attachment_path("att-1")
    assert_equal "/host/recordings/rec-1/imports", @routed.attachable_attachment_imports_path("rec-1")
    assert_equal "/host/recordings/rec-1/upload", @routed.attachable_recording_attachment_upload_path("rec-1")
  end

  def test_upload_type_labels_name_images_pdfs_text_and_leave_other_types_alone
    labels = @helper.attachable_upload_type_labels(["image/*", "application/pdf", "text/plain", "application/zip"])

    assert_equal ["images", "PDFs", "text files", "application/zip"], labels
  end

  def test_launcher_modules_keep_unique_client_picker_modules
    providers = [
      provider(client_picker: true, launcher_module: "my_cloud/picker"),
      provider(client_picker: true, launcher_module: "my_cloud/picker"),
      provider(client_picker: true, launcher_module: nil),
      provider(client_picker: false, launcher_module: "dropbox/picker")
    ]

    assert_equal ["my_cloud/picker"], @helper.upload_provider_launcher_modules(providers)
  end

  def test_js_catalogs_return_the_english_upload_picker_and_collection_copy
    upload = @helper.attachable_upload_js_i18n
    picker = @helper.attachable_picker_js_i18n
    collection = @helper.attachable_collection_js_i18n

    assert_equal "This upload provider is not available on this page.", upload["js.provider_unavailable"]
    # Locale templates keep the I18n placeholder spelling.
    # rubocop:disable Style/FormatStringToken
    assert_equal "%{type} is not allowed. Allowed types: %{types}", upload["js.type_not_allowed"]
    assert_equal "Uploading %{name}", picker["js.uploading_name"]
    # rubocop:enable Style/FormatStringToken
    assert_equal "files", upload["js.file_noun.other"]
    assert_equal "Select one or more", picker["picker.select_one_or_more"]
    assert_equal "Saved", collection["collection.saved"]
    assert_equal "Could not save.", collection["flashes.could_not_save"]
  end

  private

  def recording(recordable)
    record = Object.new
    record.define_singleton_method(:recordable) { recordable }
    record.define_singleton_method(:to_param) { "att-1" }
    record.define_singleton_method(:to_s) { "att-1" }
    record
  end

  def preview_attachment(target, variant_url: nil)
    attachment = Object.new
    attachment.define_singleton_method(:blank?) { false }
    attachment.define_singleton_method(:preview_target_named) { |_name| target }
    attachment.define_singleton_method(:url_for_variant) { |_name, rails_url:| variant_url || rails_url } if variant_url
    attachment
  end

  def provider(client_picker:, launcher_module:)
    record = Object.new
    record.define_singleton_method(:client_picker?) { client_picker }
    record.define_singleton_method(:launcher_module) { launcher_module }
    record
  end
end
