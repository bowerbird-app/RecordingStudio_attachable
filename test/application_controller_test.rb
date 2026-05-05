# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"

class ApplicationControllerTest < Minitest::Test
  class LayoutProbeController < RecordingStudioAttachable::ApplicationController; end
  FakeRecording = Struct.new(:id, :recordable_type, :parent_recording, keyword_init: true)

  def setup
    @original_layout = RecordingStudioAttachable.configuration.layout
    @controller = LayoutProbeController.new
    stub_recording_lookup!
  end

  def teardown
    RecordingStudioAttachable.configuration.layout = @original_layout
  end

  def test_blank_layout_is_default
    RecordingStudioAttachable.configuration.layout = :blank

    assert_equal "recording_studio_attachable/blank", @controller.send(:recording_studio_attachable_layout)
  end

  def test_legacy_blank_upload_alias_still_uses_blank_layout
    RecordingStudioAttachable.configuration.layout = :blank_upload

    assert_equal "recording_studio_attachable/blank", @controller.send(:recording_studio_attachable_layout)
  end

  def test_custom_layout_can_be_provided_by_host_app
    RecordingStudioAttachable.configuration.layout = "application"

    assert_equal "application", @controller.send(:recording_studio_attachable_layout)
  end

  def test_nil_layout_falls_back_to_blank_layout
    RecordingStudioAttachable.configuration.layout = nil

    assert_equal "recording_studio_attachable/blank", @controller.send(:recording_studio_attachable_layout)
  end

  def test_current_attachable_actor_prefers_current_actor
    current = ensure_current_class
    current.define_singleton_method(:actor) { :current_actor }

    assert_equal :current_actor, @controller.send(:current_attachable_actor)
  end

  def test_current_attachable_actor_falls_back_to_current_user
    current = Object.send(:remove_const, :Current) if defined?(Current)
    @controller.extend(Module.new do
      private

      def current_user
        :user
      end
    end)

    assert_equal :user, @controller.send(:current_attachable_actor)
  ensure
    Object.const_set(:Current, current) if current
  end

  def test_find_recording_delegates_to_recording_lookup
    record = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| record }

    RecordingStudio::Recording.stub(:find, record) do
      assert_equal record, @controller.send(:find_recording, "rec-1")
    end
  end

  def test_find_attachment_recording_returns_attachment_recordings
    record = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment")

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| record }

    RecordingStudio::Recording.stub(:find, record) do
      assert_equal record, @controller.send(:find_attachment_recording, "att-1")
    end
  end

  def test_find_attachment_recording_raises_for_non_attachment_recordings
    record = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| record }

    RecordingStudio::Recording.stub(:find, record) do
      assert_raises(ActiveRecord::RecordNotFound) do
        @controller.send(:find_attachment_recording, "rec-1")
      end
    end
  end

  def test_authorize_attachment_action_passes_current_actor_to_authorization
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    captured_kwargs = nil

    @controller.stub(:current_attachable_actor, :actor) do
      RecordingStudioAttachable::Authorization.stub(:authorize!, lambda { |**kwargs|
        captured_kwargs = kwargs
      }) do
        @controller.send(:authorize_attachment_action!, :view, recording, capability_options: { max_file_count: 2 })
      end
    end

    assert_equal :view, captured_kwargs[:action]
    assert_equal :actor, captured_kwargs[:actor]
    assert_equal recording, captured_kwargs[:recording]
    assert_equal({ max_file_count: 2 }, captured_kwargs[:capability_options])
  end

  def test_authorize_attachment_owner_action_uses_owner_recording_and_capability_options
    owner = FakeRecording.new(id: "owner-1", recordable_type: "Workspace")
    attachment = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment")
    captured = nil

    @controller.stub(:attachable_owner_recording, owner) do
      @controller.stub(:capability_options_for, { allowed_content_types: ["image/*"] }) do
        @controller.stub(:authorize_attachment_action!, lambda { |action, recording, capability_options:|
          captured = [action, recording, capability_options]
        }) do
          @controller.send(:authorize_attachment_owner_action!, :remove, attachment)
        end
      end
    end

    assert_equal [:remove, owner, { allowed_content_types: ["image/*"] }], captured
  end

  def test_capability_options_for_returns_empty_hash_without_owner_type
    recording = FakeRecording.new(id: "rec-1", recordable_type: nil)

    RecordingStudioAttachable::Authorization.stub(:owner_type_for, nil) do
      assert_equal({}, @controller.send(:capability_options_for, recording))
    end
  end

  def test_capability_options_for_delegates_to_recording_studio
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    RecordingStudio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| { max_file_size: 10.megabytes } }

    RecordingStudioAttachable::Authorization.stub(:owner_type_for, "Workspace") do
      RecordingStudio.stub(:capability_options, { max_file_size: 10.megabytes }) do
        assert_equal({ max_file_size: 10.megabytes }, @controller.send(:capability_options_for, recording))
      end
    end
  end

  def test_configured_attachable_option_falls_back_to_global_configuration
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

    @controller.stub(:capability_options_for, {}) do
      assert_equal :blank, @controller.send(:configured_attachable_option, recording, :layout)
    end
  end

  private

  def ensure_current_class
    return Current if defined?(Current)

    Object.const_set(:Current, Class.new)
  end

  def stub_recording_lookup!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    return if defined?(RecordingStudio::Recording)

    studio.const_set(:Recording, Class.new)
  end
end
