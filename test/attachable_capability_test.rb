# frozen_string_literal: true

require "test_helper"

class AttachableCapabilityTest < Minitest::Test
  module Probe
    HostType = Class.new
    OtherType = Class.new
  end

  def setup
    restore_recording_studio_api!
  end

  def teardown
    restore_recording_studio_api!
    reset_probe_types!
  end

  def test_to_is_a_thin_wrapper_around_include_for
    captured_name = nil
    captured_options = nil
    returned = Module.new

    RecordingStudio::Capabilities.stub(:include_for, lambda { |name, **options|
      captured_name = name
      captured_options = options
      returned
    }) do
      result = RecordingStudio::Capabilities::Attachable.to(
        max_file_count: 5,
        allowed_content_types: ["image/*"]
      )

      assert_same returned, result
    end

    assert_equal :attachable, captured_name
    assert_equal({ max_file_count: 5, allowed_content_types: ["image/*"] }, captured_options)
  end

  def test_to_enables_attachable_and_sets_options
    Probe::HostType.include(
      RecordingStudio::Capabilities::Attachable.to(
        max_file_count: 5,
        allowed_content_types: ["image/*"]
      )
    )

    assert RecordingStudio.capability_enabled?(:attachable, for: Probe::HostType)
    assert_equal(
      { max_file_count: 5, allowed_content_types: ["image/*"] },
      RecordingStudio.capability_options(:attachable, for: Probe::HostType)
    )
    refute RecordingStudio.capability_enabled?(:attachable, for: Probe::OtherType)
  end

  def test_installing_the_gem_does_not_enable_attachable
    RecordingStudioAttachable::Engine.register_recording_studio_integration

    assert RecordingStudio.registered_capabilities.key?(:attachable)
    refute RecordingStudio.capability_enabled?(:attachable, for: Probe::OtherType)
    refute RecordingStudio.capability_enabled?(:attachable, for: "UnenabledRecordable")
  end

  def test_to_does_not_register_the_capability
    register_called = false

    RecordingStudio.stub(:register_capability, lambda { |*|
      register_called = true
    }) do
      Probe::HostType.include(RecordingStudio::Capabilities::Attachable.to(max_file_count: 5))
    end

    refute register_called
    assert RecordingStudio.capability_enabled?(:attachable, for: Probe::HostType)
  end

  private

  def restore_recording_studio_api!
    singleton_class = RecordingStudio.singleton_class
    %i[configuration capability_options record! register_recordable_type register_capability enable_capability].each do |method_name|
      singleton_class.send(:remove_method, method_name) if singleton_class.method_defined?(method_name)
    end
    RecordingStudio.instance_variable_set(:@configuration, nil)
    load File.join(Gem.loaded_specs.fetch("recording_studio").full_gem_path, "lib/recording_studio.rb")
  end

  def reset_probe_types!
    Probe.send(:remove_const, :HostType) if Probe.const_defined?(:HostType, false)
    Probe.send(:remove_const, :OtherType) if Probe.const_defined?(:OtherType, false)
    Probe.const_set(:HostType, Class.new)
    Probe.const_set(:OtherType, Class.new)
  end
end
