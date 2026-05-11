# frozen_string_literal: true

require "test_helper"

class EngineTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_load_config_merges_yaml_and_x_config
    xcfg = Struct.new(:recording_studio_attachable).new({ max_file_size: 5.megabytes, image_processing_enabled: true })
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { allowed_content_types: ["image/*"], image_processing_max_width: 2048 }
      end
    end.new(app_config)

    find_initializer("recording_studio_attachable.load_config").block.call(app)

    assert_equal ["image/*"], RecordingStudioAttachable.configuration.allowed_content_types
    assert_equal 5.megabytes, RecordingStudioAttachable.configuration.max_file_size
    assert RecordingStudioAttachable.configuration.image_processing_enabled
    assert_equal 2048, RecordingStudioAttachable.configuration.image_processing_max_width
  end

  def test_assets_initializer_adds_engine_javascript_path
    assets = Struct.new(:paths).new([])
    app_config = Struct.new(:assets).new(assets)
    app = Struct.new(:config).new(app_config)

    find_initializer("recording_studio_attachable.assets").block.call(app)

    assert_includes assets.paths, RecordingStudioAttachable::Engine.root.join("app/javascript")
  end

  def test_load_config_logs_when_yaml_loading_fails
    logger = Minitest::Mock.new
    logger.expect(:warn, true, [String])
    app_config = Struct.new(:x).new(Struct.new(:recording_studio_attachable).new(nil))
    app = Struct.new(:config) do
      def config_for(_name)
        raise "bad yaml"
      end
    end.new(app_config)

    Rails.stub(:logger, logger) do
      find_initializer("recording_studio_attachable.load_config").block.call(app)
    end

    logger.verify
  end

  def test_load_yaml_config_ignores_apps_without_config_for
    app = Struct.new(:config).new(Struct.new(:x).new(nil))

    RecordingStudioAttachable::Engine.send(:load_yaml_config, app)

    assert_equal ["image/*", "application/pdf"], RecordingStudioAttachable.configuration.allowed_content_types
  end

  def test_load_yaml_config_ignores_non_enumerable_yaml_values
    app_config = Struct.new(:x).new(Struct.new(:recording_studio_attachable).new(nil))
    app = Struct.new(:config) do
      def config_for(_name)
        "not a hash"
      end
    end.new(app_config)

    RecordingStudioAttachable::Engine.send(:load_yaml_config, app)

    assert_equal 25.megabytes, RecordingStudioAttachable.configuration.max_file_size
  end

  def test_load_x_config_ignores_missing_namespace
    app = Struct.new(:config).new(Struct.new(:x).new(Object.new))

    RecordingStudioAttachable::Engine.send(:load_x_config, app)

    assert_equal 20, RecordingStudioAttachable.configuration.max_file_count
  end

  def test_load_x_config_ignores_non_hashable_values
    xcfg = Struct.new(:recording_studio_attachable).new(Object.new)
    app = Struct.new(:config).new(Struct.new(:x).new(xcfg))

    RecordingStudioAttachable::Engine.send(:load_x_config, app)

    assert_equal :blank, RecordingStudioAttachable.configuration.layout
  end

  def test_log_config_warning_uses_warn_without_a_logger
    captured_message = nil

    Rails.stub(:logger, nil) do
      RecordingStudioAttachable::Engine.stub(:warn, lambda { |message|
        captured_message = message
      }) do
        RecordingStudioAttachable::Engine.send(:log_config_warning, "fallback warning")
      end
    end

    assert_equal "fallback warning", captured_message
  end

  def test_register_initializer_registers_attachable_capability
    recordable_types = []
    capabilities = []
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)

    studio.define_singleton_method(:register_recordable_type) { |type| recordable_types << type }
    studio.define_singleton_method(:register_capability) { |name, mod| capabilities << [name, mod] }

    find_initializer("recording_studio_attachable.register_recording_studio_integration").block.call

    assert_equal ["RecordingStudioAttachable::Attachment"], recordable_types
    assert_equal [
      [:attachable, RecordingStudio::Capabilities::Attachable::RecordingMethods]
    ], capabilities
  end

  def test_google_drive_initializer_registers_provider_when_picker_is_configured
    RecordingStudioAttachable.configuration.merge!(
      google_drive: {
        enabled: true,
        client_id: "client-id",
        client_secret: "client-secret",
        redirect_uri: "https://example.test/recording_studio_attachable/google_drive/oauth/callback",
        api_key: "api-key",
        app_id: "app-id"
      }
    )
    after_initialize = nil
    app = Struct.new(:config).new(
      Object.new.tap do |config|
        config.define_singleton_method(:after_initialize) { |&block| after_initialize = block }
      end
    )

    find_google_drive_initializer("recording_studio_attachable.google_drive.register_upload_provider").block.call(app)
    after_initialize.call

    provider = RecordingStudioAttachable.configuration.upload_provider(:google_drive)
    refute_nil provider
    assert_equal "Google Drive", provider.label
    assert_equal :google_drive, provider.key
    assert_equal :client_picker, provider.strategy
    assert_equal "google_drive", provider.launcher
    assert provider.supports_remote_imports?
  end

  def test_google_drive_initializer_skips_provider_when_disabled
    after_initialize = nil
    app = Struct.new(:config).new(
      Object.new.tap do |config|
        config.define_singleton_method(:after_initialize) { |&block| after_initialize = block }
      end
    )

    find_google_drive_initializer("recording_studio_attachable.google_drive.register_upload_provider").block.call(app)
    after_initialize.call

    assert_nil RecordingStudioAttachable.configuration.upload_provider(:google_drive)
  end

  def test_google_drive_initializer_skips_provider_when_picker_configuration_is_incomplete
    RecordingStudioAttachable.configuration.merge!(
      google_drive: {
        enabled: true,
        client_id: "client-id",
        client_secret: "client-secret",
        redirect_uri: "https://example.test/recording_studio_attachable/google_drive/oauth/callback"
      }
    )
    after_initialize = nil
    app = Struct.new(:config).new(
      Object.new.tap do |config|
        config.define_singleton_method(:after_initialize) { |&block| after_initialize = block }
      end
    )

    find_google_drive_initializer("recording_studio_attachable.google_drive.register_upload_provider").block.call(app)
    after_initialize.call

    assert_nil RecordingStudioAttachable.configuration.upload_provider(:google_drive)
  end

  def test_google_drive_initializer_skips_provider_when_picker_configuration_uses_dummy_placeholders
    RecordingStudioAttachable.configuration.merge!(
      google_drive: {
        enabled: true,
        client_id: "client-id",
        client_secret: "client-secret",
        redirect_uri: "https://example.test/recording_studio_attachable/google_drive/oauth/callback",
        api_key: "dummy-google-drive-api-key",
        app_id: "dummy-google-drive-app-id"
      }
    )
    after_initialize = nil
    app = Struct.new(:config).new(
      Object.new.tap do |config|
        config.define_singleton_method(:after_initialize) { |&block| after_initialize = block }
      end
    )

    find_google_drive_initializer("recording_studio_attachable.google_drive.register_upload_provider").block.call(app)
    after_initialize.call

    assert_nil RecordingStudioAttachable.configuration.upload_provider(:google_drive)
  end

  def test_google_drive_initializer_registers_provider_with_route_helper_urls
    RecordingStudioAttachable.configuration.merge!(
      google_drive: {
        enabled: true,
        client_id: "client-id",
        client_secret: "client-secret",
        redirect_uri: "https://example.test/recording_studio_attachable/google_drive/oauth/callback",
        api_key: "api-key",
        app_id: "app-id"
      }
    )
    after_initialize = nil
    app = Struct.new(:config).new(
      Object.new.tap do |config|
        config.define_singleton_method(:after_initialize) { |&block| after_initialize = block }
      end
    )

    find_google_drive_initializer("recording_studio_attachable.google_drive.register_upload_provider").block.call(app)
    after_initialize.call

    provider = RecordingStudioAttachable.configuration.upload_provider(:google_drive)
    google_drive_proxy = Object.new
    google_drive_proxy.define_singleton_method(:recording_bootstrap_path) { |recording, format:| "/google_drive/recordings/#{recording.id}/bootstrap.#{format}" }
    google_drive_proxy.define_singleton_method(:recording_imports_path) { |recording, format:| "/google_drive/recordings/#{recording.id}/imports.#{format}" }
    route_helpers = Object.new
    route_helpers.define_singleton_method(:google_drive) { google_drive_proxy }
    view_context = Struct.new(:main_app) do
      def google_drive
        main_app.google_drive
      end
    end.new(route_helpers)
    recording = Struct.new(:id).new("rec-1")

    options = provider.button_options(view_context: view_context, recording: recording)

    assert_equal "/google_drive/recordings/rec-1/bootstrap.json", options.dig(:data, :provider_bootstrap_url)
    assert_equal "/google_drive/recordings/rec-1/imports.json", options.dig(:data, :provider_import_url)
  end

  private

  def find_initializer(name)
    RecordingStudioAttachable::Engine.initializers.find { |initializer| initializer.name == name }
  end

  def find_google_drive_initializer(name)
    RecordingStudioAttachable::GoogleDrive::Engine.initializers.find { |initializer| initializer.name == name }
  end
end
