# frozen_string_literal: true

require "test_helper"
require_relative "google_drive_fakes"
require_relative "dummy/app/models/current"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/connect_controller"

class GoogleDriveConnectControllerTest < ActionController::TestCase
  tests RecordingStudioAttachable::GoogleDrive::ConnectController

  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    RecordingStudioAttachable.configuration.google_drive.merge!(enabled: true)

    @controller = RecordingStudioAttachable::GoogleDrive::ConnectController.new
    @controller.define_singleton_method(:authorize_attachment_action!) { |_action, _recording, capability_options: {}| true }
    @controller.define_singleton_method(:capability_options_for) { |_recording| {} }
    @controller.define_singleton_method(:current_attachable_actor) { :actor }
    @controller.define_singleton_method(:google_drive_oauth_connect_path) { "/recording_studio_oauth/outbound/google_drive/connect" }
    ensure_recording_lookup!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_show_renders_oauth_connect_form_without_session_tokens
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, **kwargs|
      "/google_drive/recordings/#{record.id}/imports?#{kwargs.compact.to_query}"
    end
    route_proxy.define_singleton_method(:recording_connected_path) do |record, **kwargs|
      "/google_drive/recordings/#{record.id}/connected?#{kwargs.compact.to_query}"
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/connect",
            to: "recording_studio_attachable/google_drive/connect#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          @controller.stub(:render, lambda { |*_, **kwargs|
            @controller.response_body = [
              [
                @controller.instance_variable_get(:@oauth_connect_path),
                @controller.instance_variable_get(:@auto_submit)
              ].join(" ")
            ]
            @controller.status = kwargs[:status] || :ok
          }) do
            get :show, params: { recording_id: recording.id, popup: 1 }
          end
        end
      end
    end

    assert_response :success
    assert_includes @response.body, "/recording_studio_oauth/outbound/google_drive/connect"
    assert_includes @response.body, "true"
    assert_nil @request.session["recording_studio_attachable_google_drive"]
  end

  def test_complete_renders_provider_auth_complete_without_session_tokens
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/connected",
            to: "recording_studio_attachable/google_drive/connect#complete"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          get :complete, params: { recording_id: recording.id, popup: 1, provider_key: "google_drive" }
        end
      end
    end

    assert_response :success
    assert_includes @response.body, "provider-auth-complete"
    assert_includes @response.body, "google_drive"
    assert_includes @response.body, "window.close()"
    assert_nil @request.session["recording_studio_attachable_google_drive"]
  end

  private

  def ensure_recording_lookup!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

    return if RecordingStudio::Recording.respond_to?(:find)

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
  end
end
