# frozen_string_literal: true

require "test_helper"

class UploadProviderTest < Minitest::Test
  FakeViewContext = Struct.new(:prefix)
  FakeRecording = Struct.new(:id)
  FakeMainApp = Struct.new(:prefix)

  class CompositeViewContext
    attr_reader :main_app

    def initialize(mounted_proxy:, main_app:)
      @mounted_proxy = mounted_proxy
      @main_app = main_app
    end

    def mounted_provider
      @mounted_proxy
    end
  end

  def test_button_options_resolve_callable_url_and_target
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :google_drive,
      label: "Google Drive",
      icon: "cloud",
      url: ->(view_context:, recording:) { "#{view_context.prefix}/imports/#{recording.id}" },
      target: ->(view_context:, recording:) { "_blank" }
    )

    options = provider.button_options(view_context: FakeViewContext.new("/root"), recording: FakeRecording.new("rec-1"))

    assert_equal "Google Drive", options[:text]
    assert_equal "/root/imports/rec-1", options[:url]
    assert_equal "_blank", options[:target]
    assert_equal :secondary, options[:style]
  end

  def test_modal_button_options_open_flatpack_modal_and_pass_frame_url
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :google_drive,
      label: "Google Drive",
      url: "/recording_studio_attachable/google_drive/recordings/rec-1/imports",
      strategy: :modal_page,
      modal_title: "Google Drive picker"
    )

    options = provider.button_options(view_context: FakeViewContext.new("/root"), recording: FakeRecording.new("rec-1"))

    assert_equal "button", options[:type]
    assert_equal "recording-studio-attachable--upload#launchProvider", options.dig(:data, :action)
    assert_equal "recording-studio-attachable-provider-google_drive-rec-1-modal", options.dig(:data, :modal_id)
    assert_includes options.dig(:data, :provider_frame_url), "embed=modal"
    assert_includes options.dig(:data, :provider_frame_url), "provider_key=google_drive"
    assert_includes options.dig(:data, :provider_frame_url),
                    "provider_modal_id=recording-studio-attachable-provider-google_drive-rec-1-modal"
  end

  def test_client_picker_button_options_expose_launcher_and_bootstrap_urls
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :google_drive,
      label: "Google Drive",
      url: "/bootstrap/google_drive",
      strategy: :client_picker,
      launcher: "google_drive",
      bootstrap_url: "/bootstrap/google_drive",
      import_url: "/imports/google_drive"
    )

    options = provider.button_options(view_context: FakeViewContext.new("/root"), recording: FakeRecording.new("rec-1"))

    assert_equal "button", options[:type]
    assert_equal "recording-studio-attachable--upload#launchProvider", options.dig(:data, :action)
    assert_equal :client_picker, options.dig(:data, :provider_strategy)
    assert_equal "google_drive", options.dig(:data, :provider_launcher)
    assert_equal "/bootstrap/google_drive", options.dig(:data, :provider_bootstrap_url)
    assert_equal "/imports/google_drive", options.dig(:data, :provider_import_url)
  end

  def test_button_options_append_redirect_query_params_to_provider_urls
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :google_drive,
      label: "Google Drive",
      url: "/bootstrap/google_drive",
      strategy: :client_picker,
      launcher: "google_drive",
      bootstrap_url: "/bootstrap/google_drive",
      import_url: "/imports/google_drive"
    )

    options = provider.button_options(
      view_context: FakeViewContext.new("/root"),
      recording: FakeRecording.new("rec-1"),
      query_params: { redirect_mode: "return_to", return_to: "/pages/page-1#gallery" }
    )

    assert_includes options.dig(:data, :provider_bootstrap_url), "redirect_mode=return_to"
    assert_includes options.dig(:data, :provider_import_url), "return_to=%2Fpages%2Fpage-1%23gallery"
  end

  def test_render_returns_false_when_visible_callback_rejects_provider
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :dropbox,
      label: "Dropbox",
      url: "/imports/dropbox",
      visible: ->(view_context:, recording:) { false }
    )

    refute provider.render?(view_context: FakeViewContext.new("/root"), recording: FakeRecording.new("rec-1"))
  end

  def test_render_returns_false_when_url_resolves_blank
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :dropbox,
      label: "Dropbox",
      url: ->(view_context:, recording:) {}
    )

    refute provider.render?(view_context: FakeViewContext.new("/root"), recording: FakeRecording.new("rec-1"))
  end

  def test_render_supports_direct_and_mounted_route_helpers_from_controller_view_context
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :mounted_provider,
      label: "Mounted provider",
      url: lambda do |route_helpers:, recording:|
        [
          route_helpers.demo_upload_provider_path(recording_id: recording.id),
          route_helpers.mounted_provider.recording_imports_path(recording)
        ].join("|")
      end
    )
    mounted_proxy = Object.new
    mounted_proxy.define_singleton_method(:recording_imports_path) { |record| "/mounted_provider/recordings/#{record.id}/imports" }
    main_app = FakeMainApp.new("/upload_providers/demo")
    main_app.define_singleton_method(:demo_upload_provider_path) { |recording_id:| "/upload_providers/demo?recording_id=#{recording_id}" }
    view_context = CompositeViewContext.new(mounted_proxy: mounted_proxy, main_app: main_app)

    assert provider.render?(view_context: view_context, recording: FakeRecording.new("rec-1"))
    assert_equal "/upload_providers/demo?recording_id=rec-1|/mounted_provider/recordings/rec-1/imports",
                 provider.button_options(view_context: view_context, recording: FakeRecording.new("rec-1"))[:url]
  end

  def test_modal_provider_uses_label_for_modal_title_by_default
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :dropbox,
      label: "Dropbox",
      url: "/imports/dropbox",
      strategy: :modal_page
    )

    assert_equal "Dropbox", provider.modal_title(view_context: FakeViewContext.new("/root"), recording: FakeRecording.new("rec-1"))
  end
end
