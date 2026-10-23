# frozen_string_literal: true

require "test_helper"
require_relative "google_drive_fakes"
require_relative "dummy/app/models/current"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/bootstrap_controller"

class GoogleDriveBootstrapControllerTest < ActionController::TestCase
  tests RecordingStudioAttachable::GoogleDrive::BootstrapController

  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    RecordingStudioAttachable.configuration.google_drive.merge!(
      enabled: true,
      api_key: "api-key",
      app_id: "app-id"
    )

    @controller = RecordingStudioAttachable::GoogleDrive::BootstrapController.new
    @controller.define_singleton_method(:authorize_attachment_action!) { |_action, _recording, capability_options: {}| true }
    @controller.define_singleton_method(:capability_options_for) { |_recording| {} }
    @controller.define_singleton_method(:current_attachable_actor) { :actor }
    ensure_recording_lookup!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_show_returns_picker_bootstrap_when_connected
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, **_kwargs|
      "/google_drive/recordings/#{record.id}/imports.json"
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }
    expires_at = Time.current.to_i + 3600

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/google_drive/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Integration.stub(:picker_access, ["token-1", expires_at]) do
            get :show, params: { recording_id: recording.id, format: :json }
          end
        end
      end
    end

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal "token-1", payload.fetch("access_token")
    assert_operator payload.fetch("expires_at"), :>, Time.current.to_i + 3000
    assert_equal "api-key", payload.fetch("api_key")
    assert_equal "app-id", payload.fetch("app_id")
    assert_equal "/google_drive/recordings/rec-1/imports.json", payload.fetch("import_url")
    assert_nil @request.session["recording_studio_attachable_google_drive"]
  end

  def test_show_returns_connect_url_without_writing_session_when_reconnect_is_required
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, **_kwargs|
      "/google_drive/recordings/#{record.id}/imports.json"
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }
    @controller.define_singleton_method(:recording_connect_path) do |record, **kwargs|
      query = kwargs.compact.to_query
      "/google_drive/recordings/#{record.id}/connect#{"?#{query}" if query.present?}"
    end

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/google_drive/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Integration.stub(:picker_access, ->(*) { raise RecordingStudioGoogleDrive::ReconnectRequired, "Reconnect Google Drive" }) do
            get :show, params: { recording_id: recording.id, format: :json }
          end
        end
      end
    end

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_includes payload.fetch("connect_url"), "/google_drive/recordings/rec-1/connect"
    assert_includes payload.fetch("connect_url"), "popup=1"
    assert_not payload.key?("auth_url")
    assert_nil payload["access_token"]
    assert_nil @request.session["recording_studio_attachable_google_drive"]
  end

  def test_show_returns_forbidden_when_upload_is_denied
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @controller.define_singleton_method(:authorize_attachment_action!) do |_action, _recording, capability_options: {}|
      raise RecordingStudioAttachable::Authorization::NotAuthorizedError, "Not authorized to upload attachments for Workspace"
    end

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/google_drive/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          get :show, params: { recording_id: recording.id, format: :json }
        end
      end
    end

    assert_response :forbidden
    assert_equal "Not authorized to upload attachments for Workspace", JSON.parse(@response.body).fetch("error")
  end

  def test_show_returns_unprocessable_when_google_drive_is_disabled
    RecordingStudioAttachable.configuration.google_drive.enabled = false
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/google_drive/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        get :show, params: { recording_id: recording.id, format: :json }
      end
    end

    assert_response :unprocessable_content
    assert_equal "Google Drive isn't available right now", JSON.parse(@response.body).fetch("error")
  end

  def test_show_preserves_attachment_redirect_params_in_import_url
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, **kwargs|
      suffix = kwargs.compact.to_query
      "/google_drive/recordings/#{record.id}/imports#{"?#{suffix}" if suffix.present?}"
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/google_drive/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Integration.stub(:picker_access, ["token-1", Time.current.to_i + 3600]) do
            get :show, params: {
              recording_id: recording.id,
              format: :json,
              redirect_mode: "referer",
              return_to: "/pages/page-1#gallery"
            }
          end
        end
      end
    end

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_includes payload.fetch("import_url"), "redirect_mode=referer"
    assert_includes payload.fetch("import_url"), "return_to=%2Fpages%2Fpage-1%23gallery"
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
