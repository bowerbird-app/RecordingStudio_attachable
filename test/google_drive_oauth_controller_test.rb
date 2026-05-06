# frozen_string_literal: true

require "test_helper"
require_relative "dummy/app/models/current"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/oauth_controller"

class GoogleDriveOauthControllerTest < ActionController::TestCase
  tests RecordingStudioAttachable::GoogleDrive::OauthController

  FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    RecordingStudioAttachable.configuration.merge!(
      google_drive: {
        enabled: true,
        client_id: "client-id",
        client_secret: "client-secret",
        redirect_uri: "https://example.test/recording_studio_attachable/google_drive/oauth/callback"
      }
    )

    @controller = RecordingStudioAttachable::GoogleDrive::OauthController.new
    @controller.define_singleton_method(:authorize_attachment_action!) { |_action, _recording, capability_options: {}| true }
    @controller.define_singleton_method(:capability_options_for) { |_recording| {} }
    ensure_recording_lookup!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_new_redirects_to_google_authorization_url
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    oauth_client = Object.new
    oauth_client.define_singleton_method(:authorization_url) do |**kwargs|
      raise "missing oauth state" if kwargs[:state].blank?

      "https://accounts.google.test/auth"
    end

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/connect",
            to: "recording_studio_attachable/google_drive/oauth#new"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        @controller.stub(:oauth_client, oauth_client) do
          get :new, params: { recording_id: recording.id }
        end
      end
    end

    assert_redirected_to "https://accounts.google.test/auth"
    assert_equal recording.id, @request.session.dig("recording_studio_attachable_google_drive", "oauth_state", "recording_id")
  end

  def test_new_persists_attachment_redirect_params_in_oauth_state
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    oauth_client = Object.new
    oauth_client.define_singleton_method(:authorization_url) do |**kwargs|
      raise "missing oauth state" if kwargs[:state].blank?

      "https://accounts.google.test/auth"
    end

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/connect",
            to: "recording_studio_attachable/google_drive/oauth#new"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        @controller.stub(:oauth_client, oauth_client) do
          get :new, params: {
            recording_id: recording.id,
            redirect_mode: "return_to",
            return_to: "/pages/page-1#gallery"
          }
        end
      end
    end

    assert_redirected_to "https://accounts.google.test/auth"
    assert_equal "return_to", @request.session.dig("recording_studio_attachable_google_drive", "oauth_state", "redirect_mode")
    assert_equal "/pages/page-1#gallery", @request.session.dig("recording_studio_attachable_google_drive", "oauth_state", "return_to")
  end

  def test_callback_stores_tokens_and_redirects_back_to_the_import_page
    oauth_client = Object.new
    oauth_client.define_singleton_method(:exchange_code) do |**kwargs|
      raise "wrong code" unless kwargs[:code] == "auth-code"

      { "access_token" => "token-1", "refresh_token" => "refresh-1", "expires_at" => Time.current.to_i + 3600 }
    end
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |recording_id, **_kwargs|
      "/google_drive/recordings/#{recording_id}/imports"
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }
    @request.session["recording_studio_attachable_google_drive"] = {
      "oauth_state" => { "value" => "known-state", "recording_id" => "rec-1" }
    }

    with_routing do |set|
      set.draw do
        get "/google_drive/oauth/callback",
            to: "recording_studio_attachable/google_drive/oauth#callback"
      end

      @routes = set

      @controller.stub(:oauth_client, oauth_client) do
        get :callback, params: { state: "known-state", code: "auth-code" }
      end
    end

    assert_redirected_to "/google_drive/recordings/rec-1/imports"
    assert_equal "token-1", @request.session.dig("recording_studio_attachable_google_drive", "tokens", "access_token")
  end

  def test_callback_renders_modal_event_page_for_popup_flows
    oauth_client = Object.new
    oauth_client.define_singleton_method(:exchange_code) do |**kwargs|
      raise "wrong code" unless kwargs[:code] == "auth-code"

      { "access_token" => "token-1", "refresh_token" => "refresh-1", "expires_at" => Time.current.to_i + 3600 }
    end
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |recording_id, **kwargs|
      suffix = kwargs.compact.map { |key, value| "#{key}=#{value}" }.join("&")
      suffix = "?#{suffix}" if suffix.present?
      "/google_drive/recordings/#{recording_id}/imports#{suffix}"
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }
    @request.session["recording_studio_attachable_google_drive"] = {
      "oauth_state" => {
        "value" => "known-state",
        "recording_id" => "rec-1",
        "provider_modal_id" => "modal-1",
        "embedded" => true,
        "popup" => true
      }
    }

    with_routing do |set|
      set.draw do
        get "/google_drive/oauth/callback",
            to: "recording_studio_attachable/google_drive/oauth#callback"
      end

      @routes = set

      @controller.stub(:oauth_client, oauth_client) do
        get :callback, params: { state: "known-state", code: "auth-code" }
      end
    end

    assert_response :success
    assert_includes @response.body, "provider-auth-complete"
    assert_includes @response.body, "modal-1"
    assert_includes @response.body, "/google_drive/recordings/rec-1/imports"
    assert_includes @response.body, "window.close()"
  end

  def test_callback_renders_popup_completion_without_modal_reload_for_client_picker_flows
    oauth_client = Object.new
    oauth_client.define_singleton_method(:exchange_code) do |**kwargs|
      raise "wrong code" unless kwargs[:code] == "auth-code"

      { "access_token" => "token-1", "refresh_token" => "refresh-1", "expires_at" => Time.current.to_i + 3600 }
    end
    @request.session["recording_studio_attachable_google_drive"] = {
      "oauth_state" => {
        "value" => "known-state",
        "recording_id" => "rec-1",
        "popup" => true,
        "provider_key" => "google_drive"
      }
    }

    with_routing do |set|
      set.draw do
        get "/google_drive/oauth/callback",
            to: "recording_studio_attachable/google_drive/oauth#callback"
      end

      @routes = set

      @controller.stub(:oauth_client, oauth_client) do
        get :callback, params: { state: "known-state", code: "auth-code" }
      end
    end

    assert_response :success
    assert_includes @response.body, "provider-auth-complete"
    assert_includes @response.body, "google_drive"
    refute_includes @response.body, "/google_drive/recordings/rec-1/imports"
  end

  def test_callback_restores_attachment_redirect_params_after_auth
    oauth_client = Object.new
    oauth_client.define_singleton_method(:exchange_code) do |**kwargs|
      raise "wrong code" unless kwargs[:code] == "auth-code"

      { "access_token" => "token-1", "refresh_token" => "refresh-1", "expires_at" => Time.current.to_i + 3600 }
    end
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |recording_id, **kwargs|
      suffix = kwargs.compact.to_query
      "/google_drive/recordings/#{recording_id}/imports#{"?#{suffix}" if suffix.present?}"
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }
    @request.session["recording_studio_attachable_google_drive"] = {
      "oauth_state" => {
        "value" => "known-state",
        "recording_id" => "rec-1",
        "redirect_mode" => "return_to",
        "return_to" => "/pages/page-1#gallery"
      }
    }

    with_routing do |set|
      set.draw do
        get "/google_drive/oauth/callback",
            to: "recording_studio_attachable/google_drive/oauth#callback"
      end

      @routes = set

      @controller.stub(:oauth_client, oauth_client) do
        get :callback, params: { state: "known-state", code: "auth-code" }
      end
    end

    assert_redirected_to "/google_drive/recordings/rec-1/imports?redirect_mode=return_to&return_to=%2Fpages%2Fpage-1%23gallery"
  end

  private

  def ensure_recording_lookup!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

    return if RecordingStudio::Recording.respond_to?(:find)

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
  end
end
