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
    xcfg = Struct.new(:recording_studio_attachable).new({ max_file_size: 5.megabytes })
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { allowed_content_types: ["image/*"] }
      end
    end.new(app_config)

    find_initializer("recording_studio_attachable.load_config").block.call(app)

    assert_equal ["image/*"], RecordingStudioAttachable.configuration.allowed_content_types
    assert_equal 5.megabytes, RecordingStudioAttachable.configuration.max_file_size
  end

  def test_load_config_logs_when_yaml_loading_fails
    logger = Minitest::Mock.new
    logger.expect(:warn, true, [String])
    app_config = Struct.new(:x).new(Struct.new(:recording_studio_attachable).new(nil))
    app = Struct.new(:config) do
      def config_for(_name)
        raise RuntimeError, "bad yaml"
      end
    end.new(app_config)

    Rails.stub(:logger, logger) do
      find_initializer("recording_studio_attachable.load_config").block.call(app)
    end

    logger.verify
  end

  private

  def find_initializer(name)
    RecordingStudioAttachable::Engine.initializers.find { |initializer| initializer.name == name }
  end
end
