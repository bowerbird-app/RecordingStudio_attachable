# frozen_string_literal: true

require "test_helper"

class AuthorizationTest < Minitest::Test
  FakeRecording = Struct.new(:recordable_type, :parent_recording, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    stub_recording_studio!
    stub_accessible!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_allowed_is_false_when_attachable_capability_is_not_enabled
    recording = FakeRecording.new(recordable_type: "Workspace")

    RecordingStudio.configuration.stub(:capability_enabled?, false) do
      RecordingStudioAccessible::Authorization.stub(:allowed?, true) do
        refute RecordingStudioAttachable::Authorization.allowed?(action: :view, actor: Object.new, recording: recording)
      end
    end
  end

  def test_authorize_raises_when_attachable_capability_is_not_enabled
    recording = FakeRecording.new(recordable_type: "Workspace")

    RecordingStudio.configuration.stub(:capability_enabled?, false) do
      error = assert_raises(RecordingStudioAttachable::Authorization::CapabilityNotEnabledError) do
        RecordingStudioAttachable::Authorization.authorize!(action: :view, actor: Object.new, recording: recording)
      end

      assert_includes error.message, "Attachable capability is not enabled"
    end
  end

  def test_owner_type_for_attachment_uses_parent_recording_type
    recording = FakeRecording.new(
      recordable_type: "RecordingStudioAttachable::Attachment",
      parent_recording: FakeRecording.new(recordable_type: "Workspace")
    )

    assert_equal "Workspace", RecordingStudioAttachable::Authorization.owner_type_for(recording)
  end

  private

  def stub_recording_studio!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    configuration = Class.new do
      def capability_enabled?(*)
        true
      end
    end.new
    studio.instance_variable_set(:@test_configuration, configuration)
    return if studio.singleton_class.method_defined?(:configuration)

    studio.singleton_class.class_eval do
      define_method(:configuration) { @test_configuration }
    end
  end

  def stub_accessible!
    return if defined?(RecordingStudioAccessible::Authorization)

    accessible = Module.new
    accessible.singleton_class.class_eval do
      define_method(:allowed?) { |_actor:, _recording:, _role:| true }
    end
    Object.const_set(:RecordingStudioAccessible, Module.new) unless defined?(RecordingStudioAccessible)
    RecordingStudioAccessible.const_set(:Authorization, accessible)
  end
end
