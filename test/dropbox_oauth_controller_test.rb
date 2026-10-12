# frozen_string_literal: true

require "test_helper"
require_relative "dummy/app/models/current"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/dropbox/app/controllers/recording_studio_attachable/dropbox/application_controller"
require_relative "../lib/recording_studio_attachable/dropbox/app/controllers/recording_studio_attachable/dropbox/oauth_controller"

class DropboxOauthControllerTest < ActionController::TestCase
  tests RecordingStudioAttachable::Dropbox::OauthController

  FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    RecordingStudioAttachable.configuration.dropbox.merge!(
      enabled: true,
      client_id: "client-id",
      client_secret: "client-secret",
      redirect_uri: "https://example.test/recording_studio_attachable/dropbox/oauth/callback"
    )

    @controller = RecordingStudioAttachable::Dropbox::OauthController.new
    @controller.define_singleton_method(:authorize_attachment_action!) { |_action, _recording, capability_options: {}| true }
    @controller.define_singleton_method(:capability_options_for) { |_recording| {} }
    ensure_recording_lookup!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_new_redirects_to_dropbox_authorization_url
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    oauth_client = Object.new
    oauth_client.define_singleton_method(:authorization_url) do |**kwargs|
      raise "missing oauth state" if kwargs[:state].blank? || kwargs[:code_challenge].blank?

      "https://www.dropbox.test/auth"
    end

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/connect",
            to: "recording_studio_attachable/dropbox/oauth#new"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        @controller.stub(:oauth_client, oauth_client) do
          get :new, params: { recording_id: recording.id }
        end
      end
    end

    assert_redirected_to "https://www.dropbox.test/auth"
    assert_equal recording.id, @request.session.dig("recording_studio_attachable_dropbox", "oauth_state", "recording_id")
    assert_not_nil @request.session.dig("recording_studio_attachable_dropbox", "oauth_state", "code_verifier")
  end

  def test_callback_stores_tokens_and_redirects_back_to_the_upload_page
    oauth_client = Object.new
    oauth_client.define_singleton_method(:exchange_code) do |**kwargs|
      raise "wrong code" unless kwargs[:code] == "auth-code"
      raise "missing verifier" if kwargs[:code_verifier].blank?

      { "access_token" => "token-1", "refresh_token" => "refresh-1", "expires_at" => Time.current.to_i + 3600 }
    end
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_attachment_upload_path) do |recording_id, **_kwargs|
      "/recordings/#{recording_id}/attachments/upload"
    end
    @controller.define_singleton_method(:recording_studio_attachable) { route_proxy }
    @request.session["recording_studio_attachable_dropbox"] = {
      "oauth_state" => { "value" => "known-state", "recording_id" => "rec-1", "code_verifier" => "verifier-1" }
    }

    with_routing do |set|
      set.draw do
        get "/dropbox/oauth/callback",
            to: "recording_studio_attachable/dropbox/oauth#callback"
      end

      @routes = set

      @controller.stub(:oauth_client, oauth_client) do
        get :callback, params: { state: "known-state", code: "auth-code" }
      end
    end

    assert_redirected_to "/recordings/rec-1/attachments/upload"
    assert_equal "token-1", @request.session.dig("recording_studio_attachable_dropbox", "tokens", "access_token")
  end

  def test_callback_clears_tokens_when_the_cookie_store_overflows
    oauth_client = Object.new
    oauth_client.define_singleton_method(:exchange_code) do |**_kwargs|
      { "access_token" => "token-1", "refresh_token" => "refresh-1", "expires_at" => Time.current.to_i + 3600 }
    end
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_attachment_upload_path) do |recording_id, **_kwargs|
      "/recordings/#{recording_id}/attachments/upload"
    end
    @controller.define_singleton_method(:recording_studio_attachable) { route_proxy }
    @request.session["recording_studio_attachable_dropbox"] = {
      "oauth_state" => { "value" => "known-state", "recording_id" => "rec-1", "code_verifier" => "verifier-1" }
    }

    with_routing do |set|
      set.draw do
        get "/dropbox/oauth/callback",
            to: "recording_studio_attachable/dropbox/oauth#callback"
      end

      @routes = set

      RecordingStudioAttachable::Adapter::SessionCookie.stub(:raise_if_overflow!, lambda { |_session|
        raise ActionDispatch::Cookies::CookieOverflow
      }) do
        @controller.stub(:oauth_client, oauth_client) do
          get :callback, params: { state: "known-state", code: "auth-code" }
        end
      end
    end

    assert_redirected_to "/recordings/rec-1/attachments/upload"
    assert_equal RecordingStudioAttachable::Adapter::SessionCookie.overflow_message, flash[:alert]
    assert_nil @request.session.dig("recording_studio_attachable_dropbox", "tokens")
  end

  def test_callback_rejects_mismatched_state
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_attachment_upload_path) do |recording_id, **_kwargs|
      "/recordings/#{recording_id}/attachments/upload"
    end
    @controller.define_singleton_method(:recording_studio_attachable) { route_proxy }
    @request.session["recording_studio_attachable_dropbox"] = {
      "oauth_state" => { "value" => "known-state", "recording_id" => "rec-1", "code_verifier" => "verifier-1" }
    }

    with_routing do |set|
      set.draw do
        get "/dropbox/oauth/callback",
            to: "recording_studio_attachable/dropbox/oauth#callback"
      end

      @routes = set

      get :callback, params: { state: "wrong-state", code: "auth-code" }
    end

    assert_redirected_to "/recordings/rec-1/attachments/upload"
    assert_equal "Dropbox authorization state did not match", flash[:alert]
  end

  def test_callback_redirects_to_root_when_state_fails_without_a_recording
    main_app = Object.new
    main_app.define_singleton_method(:root_path) { "/" }
    @controller.define_singleton_method(:main_app) { main_app }

    with_routing do |set|
      set.draw do
        get "/dropbox/oauth/callback",
            to: "recording_studio_attachable/dropbox/oauth#callback"
      end

      @routes = set

      get :callback, params: { state: "wrong-state", code: "auth-code" }
    end

    assert_redirected_to "/"
    assert_equal "Dropbox authorization state did not match", flash[:alert]
  end

  def test_destroy_clears_tokens_and_redirects_back_to_upload
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_attachment_upload_path) do |record, options = {}|
      suffix = options.compact.to_query
      path = "/recordings/#{record.id}/attachments/upload"
      suffix.present? ? "#{path}?#{suffix}" : path
    end
    @controller.define_singleton_method(:recording_studio_attachable) { route_proxy }
    @request.session["recording_studio_attachable_dropbox"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
    }

    with_routing do |set|
      set.draw do
        delete "/dropbox/recordings/:recording_id/connect",
               to: "recording_studio_attachable/dropbox/oauth#destroy"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        @controller.stub(:protect_against_forgery?, false) do
          delete :destroy, params: { recording_id: recording.id }
        end
      end
    end

    assert_redirected_to "/recordings/rec-1/attachments/upload"
    assert_nil @request.session.dig("recording_studio_attachable_dropbox", "tokens")
  end

  private

  def ensure_recording_lookup!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

    return if RecordingStudio::Recording.respond_to?(:find)

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
  end
end
