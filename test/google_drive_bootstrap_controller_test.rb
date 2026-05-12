# frozen_string_literal: true

require "test_helper"
require_relative "dummy/app/models/current"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/bootstrap_controller"

class GoogleDriveBootstrapControllerTest < ActionController::TestCase
  tests RecordingStudioAttachable::GoogleDrive::BootstrapController

  FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    RecordingStudioAttachable.configuration.google_drive.merge!(
      enabled: true,
      client_id: "client-id",
      client_secret: "client-secret",
      redirect_uri: "https://example.test/recording_studio_attachable/google_drive/oauth/callback",
      api_key: "api-key",
      app_id: "app-id"
    )

    @controller = RecordingStudioAttachable::GoogleDrive::BootstrapController.new
    @controller.define_singleton_method(:authorize_attachment_action!) { |_action, _recording, capability_options: {}| true }
    @controller.define_singleton_method(:capability_options_for) { |_recording| {} }
    ensure_recording_lookup!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_show_returns_picker_bootstrap_when_connected
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @request.session["recording_studio_attachable_google_drive"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
    }
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, **_kwargs|
      "/google_drive/recordings/#{record.id}/imports.json"
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }

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

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal "token-1", payload.fetch("access_token")
    assert_equal "api-key", payload.fetch("api_key")
    assert_equal "app-id", payload.fetch("app_id")
    assert_equal "/google_drive/recordings/rec-1/imports.json", payload.fetch("import_url")
  end

  def test_show_returns_auth_url_when_not_connected
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, **_kwargs|
      "/google_drive/recordings/#{record.id}/imports.json"
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }
    oauth_client = Object.new
    oauth_client.define_singleton_method(:authorization_url) do |**kwargs|
      raise "missing oauth state" if kwargs[:state].blank?

      "https://accounts.google.test/auth"
    end

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/google_drive/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        @controller.stub(:oauth_client, oauth_client) do
          get :show, params: { recording_id: recording.id, format: :json }
        end
      end
    end

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal "https://accounts.google.test/auth", payload.fetch("auth_url")
    assert_nil payload["access_token"]
  end

  def test_show_preserves_attachment_redirect_params_in_import_url
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @request.session["recording_studio_attachable_google_drive"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
    }
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
        get :show, params: {
          recording_id: recording.id,
          format: :json,
          redirect_mode: "referer",
          return_to: "/pages/page-1#gallery"
        }
      end
    end

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_includes payload.fetch("import_url"), "redirect_mode=referer"
    assert_includes payload.fetch("import_url"), "return_to=%2Fpages%2Fpage-1%23gallery"
  end

  private

  def ensure_recording_lookup!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

    return if RecordingStudio::Recording.respond_to?(:find)

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
  end
end
