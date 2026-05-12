# frozen_string_literal: true

require "test_helper"

class AttachableCapabilityTest < Minitest::Test
  def test_to_registers_capability_options_and_attachment_recordable_type_when_recording_studio_is_loaded
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    enabled = []
    options_calls = []
    recordable_types = []

    studio.define_singleton_method(:enable_capability) { |name, on:| enabled << [name, on] }
    studio.define_singleton_method(:set_capability_options) { |name, on:, **options| options_calls << [name, on, options] }
    studio.define_singleton_method(:register_recordable_type) { |type| recordable_types << type }

    klass = Class.new do
      def self.name
        "ExampleRecord"
      end

      include RecordingStudio::Capabilities::Attachable.to(max_file_count: 5)
    end

    assert_equal "ExampleRecord", klass.name
    assert_equal [[:attachable, "ExampleRecord"]], enabled
    assert_equal [[:attachable, "ExampleRecord", { max_file_count: 5 }]], options_calls
    assert_equal ["RecordingStudioAttachable::Attachment"], recordable_types
  end

  def test_to_skips_registration_when_recording_studio_is_not_loaded
    concern = RecordingStudio::Capabilities::Attachable
    original = Object.send(:remove_const, :RecordingStudio) if defined?(RecordingStudio)

    klass = Class.new do
      include concern.to(max_file_count: 5)
    end

    assert klass
  ensure
    Object.const_set(:RecordingStudio, original) if original
  end
end
