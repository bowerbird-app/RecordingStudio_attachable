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

  def test_supports_remote_imports_is_true_when_hook_is_registered
    importer = ->(**) { :ok }
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :google_drive,
      label: "Google Drive",
      url: "/bootstrap/google_drive",
      strategy: :client_picker,
      launcher: "google_drive",
      remote_importer: importer
    )

    assert provider.supports_remote_imports?
    assert_same importer, provider.remote_importer
  end

  def test_initialize_rejects_non_callable_remote_importers
    error = assert_raises(ArgumentError) do
      RecordingStudioAttachable::UploadProvider.new(
        key: :google_drive,
        label: "Google Drive",
        url: "/bootstrap/google_drive",
        remote_importer: Object.new
      )
    end

    assert_equal "remote_importer must respond to #call", error.message
  end

  def test_import_remote_attachments_forwards_full_hook_context
    captured = nil
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :google_drive,
      label: "Google Drive",
      url: "/bootstrap/google_drive",
      remote_importer: lambda { |**kwargs|
        captured = kwargs
        :result
      }
    )
    context = Struct.new(:session).new({ "token" => "abc" })

    result = provider.import_remote_attachments(
      parent_recording: FakeRecording.new("rec-1"),
      attachments: [{ provider_payload: { id: "file-1" } }],
      actor: :actor,
      impersonator: :impersonator,
      context: context
    )

    assert_equal :result, result
    assert_equal :actor, captured[:actor]
    assert_equal :impersonator, captured[:impersonator]
    assert_same context, captured[:context]
  end

  def test_render_returns_false_when_visible_callback_rejects_provider
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :dropbox,
      label: "Dropbox",
      url: "/imports/dropbox",
      visible: ->(view_context:, recording:) { false }
    )

    assert_not provider.render?(view_context: FakeViewContext.new("/root"), recording: FakeRecording.new("rec-1"))
  end

  def test_render_returns_false_when_url_resolves_blank
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :dropbox,
      label: "Dropbox",
      url: ->(view_context:, recording:) {}
    )

    assert_not provider.render?(view_context: FakeViewContext.new("/root"), recording: FakeRecording.new("rec-1"))
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

  def test_iframe_title_uses_custom_value_and_falls_back_to_label
    custom_provider = RecordingStudioAttachable::UploadProvider.new(
      key: :google_drive,
      label: "Google Drive",
      url: "/imports/google_drive",
      iframe_title: ->(recording:) { "Picker for #{recording.id}" }
    )
    default_provider = RecordingStudioAttachable::UploadProvider.new(
      key: :dropbox,
      label: "Dropbox",
      url: "/imports/dropbox"
    )

    assert_equal "Picker for rec-1",
                 custom_provider.iframe_title(view_context: FakeViewContext.new("/root"), recording: FakeRecording.new("rec-1"))
    assert_equal "Dropbox picker",
                 default_provider.iframe_title(view_context: FakeViewContext.new("/root"), recording: FakeRecording.new("rec-2"))
  end

  def test_initialize_rejects_unknown_strategies
    error = assert_raises(ArgumentError) do
      RecordingStudioAttachable::UploadProvider.new(
        key: :google_drive,
        label: "Google Drive",
        url: "/imports/google_drive",
        strategy: :drawer
      )
    end

    assert_equal "Unknown upload provider strategy: :drawer", error.message
  end

  def test_render_supports_client_picker_and_legacy_callable_arities
    two_arg_provider = RecordingStudioAttachable::UploadProvider.new(
      key: :legacy_two,
      label: "Legacy two",
      url: ->(route_helpers, recording) { "#{route_helpers.prefix}/legacy/#{recording.id}" },
      strategy: :client_picker
    )
    one_arg_provider = RecordingStudioAttachable::UploadProvider.new(
      key: :legacy_one,
      label: "Legacy one",
      url: ->(recording) { "/legacy/#{recording.id}" }
    )
    zero_arg_provider = RecordingStudioAttachable::UploadProvider.new(
      key: :legacy_zero,
      label: "Legacy zero",
      url: -> { "/legacy/static" }
    )
    view_context = FakeViewContext.new("/root")
    recording = FakeRecording.new("rec-1")

    assert two_arg_provider.render?(view_context: view_context, recording: recording)
    assert_equal "/root/legacy/rec-1",
                 two_arg_provider.button_options(view_context: view_context, recording: recording)[:data][:provider_bootstrap_url]
    assert_equal "/legacy/rec-1", one_arg_provider.button_options(view_context: view_context, recording: recording)[:url]
    assert_equal "/legacy/static", zero_arg_provider.button_options(view_context: view_context, recording: recording)[:url]
  end

  def test_route_helpers_proxy_uses_main_app_and_raises_for_unknown_methods
    main_app = Object.new
    main_app.define_singleton_method(:demo_path) { "/main/demo" }
    view_context = Struct.new(:main_app).new(main_app)
    proxy = RecordingStudioAttachable::UploadProvider::RouteHelpersProxy.new(view_context)

    assert_equal "/main/demo", proxy.demo_path
    assert proxy.respond_to?(:demo_path)
    assert_not proxy.respond_to?(:missing_path)
    assert_raises(NoMethodError) { proxy.missing_path }
  end

  def test_route_helpers_proxy_prefers_view_context_methods_over_main_app
    main_app = Object.new
    main_app.define_singleton_method(:demo_path) { "/main/demo" }
    view_context = Struct.new(:main_app).new(main_app)
    view_context.define_singleton_method(:demo_path) { "/view/demo" }

    proxy = RecordingStudioAttachable::UploadProvider::RouteHelpersProxy.new(view_context)

    assert_equal "/view/demo", proxy.demo_path
  end

  def test_modal_button_options_merge_existing_actions_and_rewrite_invalid_modal_urls
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :google_drive,
      label: "Google Drive",
      url: "https://example.test/%zz",
      strategy: :modal_page,
      data: { action: "analytics#track", source: "toolbar" },
      class: "provider-button"
    )

    options = provider.button_options(view_context: FakeViewContext.new("/root"), recording: FakeRecording.new("rec-1"))

    assert_equal "analytics#track recording-studio-attachable--upload#launchProvider", options.dig(:data, :action)
    assert_equal "toolbar", options.dig(:data, :source)
    assert_equal "provider-button", options[:class]
    assert_includes options.dig(:data, :provider_frame_url), "embed=modal"
    assert_includes options.dig(:data, :provider_frame_url), "provider_key=google_drive"
  end

  def test_button_options_append_query_params_for_invalid_urls_without_parsing
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :dropbox,
      label: "Dropbox",
      url: "https://example.test/%zz"
    )

    options = provider.button_options(
      view_context: FakeViewContext.new("/root"),
      recording: FakeRecording.new("rec-1"),
      query_params: { redirect_mode: "return_to", return_to: "/pages/page-1" }
    )

    assert_includes options[:url], "redirect_mode=return_to"
    assert_includes options[:url], "return_to=%2Fpages%2Fpage-1"
  end

  def test_modal_button_options_allow_blank_urls_without_rendering_frame_url
    provider = RecordingStudioAttachable::UploadProvider.new(
      key: :google_drive,
      label: "Google Drive",
      url: ->(**) {},
      strategy: :modal_page
    )

    assert_not provider.render?(view_context: FakeViewContext.new("/root"), recording: FakeRecording.new("rec-1"))
  end
end
