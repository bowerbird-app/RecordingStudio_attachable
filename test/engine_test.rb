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

    assert_nil RecordingStudioAttachable.configuration.layout
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
    after_initialize = nil
    app = Struct.new(:config).new(
      Object.new.tap do |config|
        config.define_singleton_method(:after_initialize) { |&block| after_initialize = block }
      end
    )
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)

    RecordingStudioAttachable::Engine.stub(
      :register_attachment_recordable_type,
      -> { recordable_types << "RecordingStudioAttachable::Attachment" }
    ) do
      studio.stub(:register_capability, ->(name, mod = nil, **kwargs) { capabilities << [name, mod, kwargs] }) do
        find_initializer("recording_studio_attachable.register_recording_studio_integration").block.call(app)
      end
    end

    assert_equal ["RecordingStudioAttachable::Attachment"], recordable_types
    assert_equal expected_registered_capabilities, capabilities
    assert_not_nil after_initialize
  end

  def test_register_initializer_re_registers_attachment_type_after_app_initializers
    recordable_types = []
    capabilities = []
    app = Struct.new(:config).new(
      Object.new.tap do |config|
        config.define_singleton_method(:after_initialize) { |&block| @after_initialize = block }
        config.define_singleton_method(:run_after_initialize) { @after_initialize.call }
      end
    )
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)

    RecordingStudioAttachable::Engine.stub(
      :register_attachment_recordable_type,
      -> { recordable_types << "RecordingStudioAttachable::Attachment" }
    ) do
      studio.stub(:register_capability, ->(name, mod = nil, **kwargs) { capabilities << [name, mod, kwargs] }) do
        find_initializer("recording_studio_attachable.register_recording_studio_integration").block.call(app)
        recordable_types.clear
        capabilities.clear
        app.config.run_after_initialize
      end
    end

    assert_equal ["RecordingStudioAttachable::Attachment"], recordable_types
    assert_equal expected_registered_capabilities, capabilities
  end

  def test_register_initializer_skips_re_registering_attachment_when_already_configured
    capabilities = []
    app = Struct.new(:config).new(
      Object.new.tap do |config|
        config.define_singleton_method(:after_initialize) { |&block| }
      end
    )
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    configuration = Struct.new(:recordable_types).new(["Workspace", "RecordingStudioAttachable::Attachment"])
    register_recordable_type_called = false

    RecordingStudioAttachable::Engine.stub(:attachable_parent_types_registered?, true) do
      studio.stub(:configuration, configuration) do
        studio.stub(:register_recordable_type, ->(*) { register_recordable_type_called = true }) do
          studio.stub(:register_capability, ->(name, mod = nil, **kwargs) { capabilities << [name, mod, kwargs] }) do
            find_initializer("recording_studio_attachable.register_recording_studio_integration").block.call(app)
          end
        end
      end
    end

    assert_not register_recordable_type_called
    assert_equal expected_registered_capabilities, capabilities
  end

  private

  def find_initializer(name)
    RecordingStudioAttachable::Engine.initializers.find { |initializer| initializer.name == name }
  end

  def expected_registered_capabilities
    [
      [
        :attachable,
        nil,
        {
          recording_methods: RecordingStudio::Capabilities::Attachable::RecordingMethods,
          source: "recording_studio_attachable",
          child_recordables: ["RecordingStudioAttachable::Attachment"]
        }
      ]
    ]
  end
end
