# frozen_string_literal: true

require "test_helper"
require "action_controller"

require File.join(
  Gem.loaded_specs.fetch("recording_studio").full_gem_path,
  "app/helpers/recording_studio/layout_helper"
)

class LayoutConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAttachable::Configuration.new
    @previous_attachable = RecordingStudioAttachable.instance_variable_get(:@configuration)
    @previous_studio_configuration = RecordingStudio.method(:configuration)
    studio_configuration = RecordingStudio::Configuration.new
    RecordingStudio.define_singleton_method(:configuration) { studio_configuration }
    RecordingStudioAttachable.instance_variable_set(:@configuration, @configuration)
  end

  def teardown
    RecordingStudio.define_singleton_method(:configuration, @previous_studio_configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, @previous_attachable)
  end

  def test_layout_defaults_to_nil
    assert_nil @configuration.layout
    assert_nil @configuration.to_h.fetch(:layout)
  end

  def test_nil_layout_falls_through_to_recording_studio_then_the_default_name
    RecordingStudio.configuration.layout = nil

    assert_equal "recording_studio/default_layout", probe.recording_studio_resolved_layout

    RecordingStudio.configuration.layout = "host_pages"
    assert_equal "host_pages", probe.recording_studio_resolved_layout
  end

  def test_string_layout_is_used_as_the_layout_name
    @configuration.layout = "attachable_pages"

    assert_equal "attachable_pages", probe.recording_studio_resolved_layout
  end

  def test_false_layout_renders_no_layout
    @configuration.layout = false

    assert_equal false, probe.recording_studio_resolved_layout
  end

  def test_keyword_callable_receives_the_controller
    @configuration.layout = ->(controller:) { controller.class.name }

    assert_equal "AttachableLayoutProbeController", probe.recording_studio_resolved_layout
  end

  def test_invalid_layout_values_raise_argument_error
    assert_raises(ArgumentError) { @configuration.layout = "" }
    assert_raises(ArgumentError) { @configuration.layout = :blank }
    assert_raises(ArgumentError) { @configuration.layout = 1 }
    assert_raises(ArgumentError) { @configuration.layout = ->(controller) { controller.class.name } }
    assert_raises(ArgumentError) { @configuration.layout = -> { "pages" } }
  end

  def test_controllers_do_not_hardcode_a_recording_studio_layout
    gem_root = File.expand_path("..", __dir__)
    dummy_root = File.expand_path("dummy", __dir__)

    assert_empty RecordingStudio::Layout.hardcoded_layout_paths(gem_root)
    assert_empty RecordingStudio::Layout.hardcoded_layout_paths(dummy_root)
  end

  private

  def probe
    AttachableLayoutProbeController.new
  end
end

class AttachableLayoutProbeController < ActionController::Base
  include RecordingStudio::ControllerLayout

  recording_studio_layout { RecordingStudioAttachable.configuration.layout }
end
