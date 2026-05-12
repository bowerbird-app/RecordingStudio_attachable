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
        assert_not RecordingStudioAttachable::Authorization.allowed?(action: :view, actor: Object.new, recording: recording)
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

  def test_authorize_returns_true_when_actor_is_allowed
    recording = FakeRecording.new(recordable_type: "Workspace")

    RecordingStudio.configuration.stub(:capability_enabled?, true) do
      RecordingStudioAccessible::Authorization.stub(:allowed?, true) do
        assert RecordingStudioAttachable::Authorization.authorize!(
          action: :view,
          actor: Object.new,
          recording: recording
        )
      end
    end
  end

  def test_allowed_uses_custom_adapter_and_merged_role_overrides
    recording = FakeRecording.new(recordable_type: "Workspace")
    captured_kwargs = nil
    adapter = lambda do |**kwargs|
      captured_kwargs = kwargs
      true
    end

    result = RecordingStudioAttachable::Authorization.allowed?(
      action: :view,
      actor: :user,
      recording: recording,
      capability_options: {
        authorize_with: adapter,
        auth_roles: { view: :admin }
      }
    )

    assert result
    assert_equal :admin, captured_kwargs[:role]
    assert_equal :user, captured_kwargs[:actor]
    assert_equal recording, captured_kwargs[:recording]
  end

  def test_authorization_adapter_falls_back_to_global_configuration
    adapter = ->(**) { true }
    RecordingStudioAttachable.configuration.authorize_with = adapter

    assert_equal adapter, RecordingStudioAttachable::Authorization.authorization_adapter({})
  end

  def test_authorization_adapter_prefers_capability_option_over_global_configuration
    global_adapter = ->(**) { true }
    local_adapter = ->(**) { false }
    RecordingStudioAttachable.configuration.authorize_with = global_adapter

    assert_equal local_adapter,
                 RecordingStudioAttachable::Authorization.authorization_adapter(authorize_with: local_adapter)
  end

  def test_required_role_for_prefers_capability_role_overrides
    role = RecordingStudioAttachable::Authorization.required_role_for(
      :download,
      capability_options: { auth_roles: { download: :admin } }
    )

    assert_equal :admin, role
  end

  def test_allowed_is_false_without_accessible_fallback
    recording = FakeRecording.new(recordable_type: "Workspace")
    accessible = RecordingStudioAccessible.send(:remove_const, :Authorization)

    begin
      assert_not RecordingStudioAttachable::Authorization.allowed?(
        action: :view,
        actor: Object.new,
        recording: recording
      )
    ensure
      RecordingStudioAccessible.const_set(:Authorization, accessible)
    end
  end

  def test_attachable_enabled_is_false_when_owner_type_is_blank
    recording = FakeRecording.new(recordable_type: nil)

    assert_not RecordingStudioAttachable::Authorization.attachable_enabled?(recording: recording)
  end

  def test_attachable_enabled_uses_capability_options_without_recording_studio
    recording = FakeRecording.new(recordable_type: "Workspace")
    studio = Object.send(:remove_const, :RecordingStudio)

    begin
      assert RecordingStudioAttachable::Authorization.attachable_enabled?(
        recording: recording,
        capability_options: { max_file_count: 1 }
      )
      assert_not RecordingStudioAttachable::Authorization.attachable_enabled?(
        recording: recording,
        capability_options: nil
      )
    ensure
      Object.const_set(:RecordingStudio, studio)
    end
  end

  def test_owner_recording_for_returns_original_object_without_recordable_type
    object = Object.new

    assert_same object, RecordingStudioAttachable::Authorization.owner_recording_for(object)
  end

  def test_owner_recording_for_returns_parent_for_attachment_recordings
    parent = FakeRecording.new(recordable_type: "Workspace")
    recording = FakeRecording.new(recordable_type: "RecordingStudioAttachable::Attachment", parent_recording: parent)

    assert_same parent, RecordingStudioAttachable::Authorization.owner_recording_for(recording)
  end

  def test_allowed_is_false_when_required_role_is_blank
    recording = FakeRecording.new(recordable_type: "Workspace")

    RecordingStudio.configuration.stub(:capability_enabled?, true) do
      assert_not RecordingStudioAttachable::Authorization.allowed?(
        action: :view,
        actor: Object.new,
        recording: recording,
        capability_options: { auth_roles: { view: nil } }
      )
    end
  end

  def test_authorize_raises_when_custom_adapter_denies_access
    recording = FakeRecording.new(recordable_type: "Workspace")

    error = assert_raises(RecordingStudioAttachable::Authorization::NotAuthorizedError) do
      RecordingStudioAttachable::Authorization.authorize!(
        action: :view,
        actor: :user,
        recording: recording,
        capability_options: { authorize_with: ->(**) { false } }
      )
    end

    assert_equal "Not authorized to view attachments for Workspace", error.message
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
    studio.singleton_class.send(:remove_method, :configuration) if studio.singleton_class.method_defined?(:configuration)
    studio.define_singleton_method(:configuration) { @test_configuration }
  end

  def stub_accessible!
    return if defined?(RecordingStudioAccessible::Authorization)

    accessible = Module.new
    accessible.singleton_class.class_eval do
      define_method(:allowed?) { |actor:, recording:, role:| actor || recording || role || true }
    end
    Object.const_set(:RecordingStudioAccessible, Module.new) unless defined?(RecordingStudioAccessible)
    RecordingStudioAccessible.const_set(:Authorization, accessible)
  end
end
