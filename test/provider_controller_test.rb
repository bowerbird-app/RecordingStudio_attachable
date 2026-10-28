# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/provider_controller"

class ProviderControllerTest < Minitest::Test
  class ProbeController < RecordingStudioAttachable::ProviderController; end
  FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

  def setup
    @controller = ProbeController.new
    stub_recording_lookup!
  end

  def test_authorize_provider_upload_allows_the_upload_action_on_the_found_recording
    recording = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
    captured = nil

    @controller.stub(:find_recording, recording) do
      @controller.stub(:capability_options_for, { max_file_count: 2 }) do
        RecordingStudioAttachable::Authorization.stub(:authorize!, lambda { |**kwargs|
          captured = kwargs
          true
        }) do
          @controller.stub(:current_attachable_actor, :actor) do
            assert_equal true, @controller.send(:authorize_provider_upload!)
          end
        end
      end
    end

    assert_equal recording, @controller.instance_variable_get(:@recording)
    assert_equal :upload, captured[:action]
    assert_equal :actor, captured[:actor]
    assert_equal recording, captured[:recording]
    assert_equal({ max_file_count: 2 }, captured[:capability_options])
  end

  def test_authorize_provider_upload_rejects_when_upload_is_not_allowed
    recording = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
    error = RecordingStudioAttachable::Authorization::NotAuthorizedError.new("Not allowed")

    @controller.stub(:find_recording, recording) do
      @controller.stub(:capability_options_for, {}) do
        RecordingStudioAttachable::Authorization.stub(:authorize!, ->(**) { raise error }) do
          @controller.stub(:current_attachable_actor, :actor) do
            raised = assert_raises(RecordingStudioAttachable::Authorization::NotAuthorizedError) do
              @controller.send(:authorize_provider_upload!)
            end

            assert_equal "Not allowed", raised.message
          end
        end
      end
    end
  end

  def test_authorize_provider_upload_rejects_a_missing_recording
    @controller.stub(:find_recording, -> { raise ActiveRecord::RecordNotFound }) do
      assert_raises(ActiveRecord::RecordNotFound) do
        @controller.send(:authorize_provider_upload!)
      end
    end
  end

  private

  def stub_recording_lookup!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    return if defined?(RecordingStudio::Recording)

    studio.const_set(:Recording, Class.new)
  end
end
