# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/provider_controller"

class ProviderControllerTest < Minitest::Test
  class ProbeController < RecordingStudioAttachable::ProviderController; end
  FakeRecording = Struct.new(:id, :recordable_type, :parent_recording, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    @controller = ProbeController.new
    @request = ActionDispatch::TestRequest.create
    @response = ActionDispatch::TestResponse.create
    @controller.set_request!(@request)
    @controller.set_response!(@response)
    stub_recording_lookup!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_authorize_provider_upload_allows_an_actor_who_can_upload
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

    RecordingStudio.configuration.stub(:capability_enabled?, true) do
      @controller.stub(:find_recording, recording) do
        @controller.stub(:current_attachable_actor, :actor) do
          @controller.stub(:capability_options_for, { authorize_with: ->(**) { true } }) do
            assert @controller.send(:authorize_provider_upload!)
            assert_equal recording, @controller.instance_variable_get(:@recording)
          end
        end
      end
    end
  end

  def test_authorize_provider_upload_rejects_when_upload_is_not_allowed
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

    RecordingStudio.configuration.stub(:capability_enabled?, true) do
      @controller.stub(:find_recording, recording) do
        @controller.stub(:current_attachable_actor, :actor) do
          @controller.stub(:capability_options_for, { authorize_with: ->(**) { false } }) do
            error = assert_raises(RecordingStudioAttachable::Authorization::NotAuthorizedError) do
              @controller.send(:authorize_provider_upload!)
            end

            assert_includes error.message, "upload"
            assert_equal recording, @controller.instance_variable_get(:@recording)
          end
        end
      end
    end
  end

  def test_authorize_provider_upload_rejects_when_attachable_is_not_enabled
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

    RecordingStudio.configuration.stub(:capability_enabled?, false) do
      @controller.stub(:find_recording, recording) do
        @controller.stub(:current_attachable_actor, :actor) do
          error = assert_raises(RecordingStudioAttachable::Authorization::CapabilityNotEnabledError) do
            @controller.send(:authorize_provider_upload!)
          end

          assert_includes error.message, "Attachable capability is not enabled"
        end
      end
    end
  end

  def test_authorize_provider_upload_rejects_a_missing_recording
    @controller.params = ActionController::Parameters.new(recording_id: "missing")
    RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }

    RecordingStudio::Recording.stub(:find, ->(_id) { raise ActiveRecord::RecordNotFound }) do
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
