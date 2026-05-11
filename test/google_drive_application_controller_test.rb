# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/application_controller"

class GoogleDriveApplicationControllerTest < Minitest::Test
  class ProbeController < RecordingStudioAttachable::GoogleDrive::ApplicationController
    def recording_studio_attachable
      @recording_studio_attachable ||= Object.new.tap do |proxy|
        proxy.define_singleton_method(:recording_attachment_upload_path) do |recording, _query = {}|
          "/recordings/#{recording.id}/attachment_upload"
        end
      end
    end
  end

  FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    @controller = ProbeController.new
    @request = ActionDispatch::TestRequest.create
    @response = ActionDispatch::TestResponse.create
    @session = {}
    @controller.set_request!(@request)
    @controller.set_response!(@response)
    @controller.define_singleton_method(:session) { @test_session }
    @controller.instance_variable_set(:@test_session, @session)
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_ensure_google_drive_enabled_requires_the_addon_to_be_enabled
    error = assert_raises(RecordingStudioAttachable::DependencyUnavailableError) do
      @controller.send(:ensure_google_drive_enabled!)
    end

    assert_equal "Google Drive addon is not enabled", error.message
  end

  def test_ensure_google_drive_enabled_requires_client_credentials
    RecordingStudioAttachable.configuration.merge!(google_drive: { enabled: true })

    error = assert_raises(RecordingStudioAttachable::DependencyUnavailableError) do
      @controller.send(:ensure_google_drive_enabled!)
    end

    assert_equal "Google Drive addon is missing client credentials or redirect URI", error.message
  end

  def test_ensure_google_drive_picker_configured_requires_picker_keys
    RecordingStudioAttachable.configuration.merge!(
      google_drive: {
        enabled: true,
        client_id: "client-id",
        client_secret: "client-secret",
        redirect_uri: "https://example.test/oauth/callback"
      }
    )

    error = assert_raises(RecordingStudioAttachable::DependencyUnavailableError) do
      @controller.send(:ensure_google_drive_picker_configured!)
    end

    assert_equal "Google Drive picker requires api_key and app_id configuration", error.message
  end

  def test_ensure_google_drive_picker_configured_rejects_dummy_placeholder_picker_values
    RecordingStudioAttachable.configuration.merge!(
      google_drive: {
        enabled: true,
        client_id: "client-id",
        client_secret: "client-secret",
        redirect_uri: "https://example.test/oauth/callback",
        api_key: "dummy-google-drive-api-key",
        app_id: "dummy-google-drive-app-id"
      }
    )

    error = assert_raises(RecordingStudioAttachable::DependencyUnavailableError) do
      @controller.send(:ensure_google_drive_picker_configured!)
    end

    assert_equal "Google Drive picker requires api_key and app_id configuration", error.message
  end

  def test_google_drive_connected_uses_session_tokens
    refute @controller.send(:google_drive_connected?)

    @controller.send(:store_google_drive_tokens!, access_token: "token-1")

    assert @controller.send(:google_drive_connected?)
  end

  def test_store_and_clear_google_drive_tokens_manage_session_data
    @controller.send(:store_google_drive_tokens!, access_token: "token-1", refresh_token: "refresh-1", expires_at: nil)

    assert_equal(
      { "access_token" => "token-1", "refresh_token" => "refresh-1" },
      @controller.send(:google_drive_tokens)
    )

    @controller.send(:clear_google_drive_tokens!)

    assert_equal({}, @controller.send(:google_drive_tokens))
  end

  def test_store_and_consume_google_drive_state_round_trip
    state = @controller.send(
      :store_google_drive_state!,
      recording_id: "rec-1",
      popup: true,
      provider_key: "google_drive",
      redirect_params: { redirect_mode: "return_to", return_to: "/pages/demo" }
    )

    payload = @controller.send(:consume_google_drive_state!, state)

    assert_equal "rec-1", payload.fetch("recording_id")
    assert_equal true, payload.fetch("popup")
    assert_equal "google_drive", payload.fetch("provider_key")
    assert_equal "/pages/demo", payload.fetch("return_to")
    assert_nil @session.dig("recording_studio_attachable_google_drive", "oauth_state")
  end

  def test_consume_google_drive_state_rejects_mismatched_values
    @session["recording_studio_attachable_google_drive"] = {
      "oauth_state" => { "value" => "expected" }
    }

    error = assert_raises(RecordingStudioAttachable::Error) do
      @controller.send(:consume_google_drive_state!, "actual")
    end

    assert_equal "Google Drive authorization state did not match", error.message
  end

  def test_current_google_drive_access_token_returns_existing_valid_token
    @session["recording_studio_attachable_google_drive"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 300 }
    }

    assert_equal "token-1", @controller.send(:current_google_drive_access_token)
  end

  def test_current_google_drive_access_token_refreshes_expired_tokens_and_updates_session
    @session["recording_studio_attachable_google_drive"] = {
      "tokens" => {
        "access_token" => "expired",
        "refresh_token" => "refresh-1",
        "expires_at" => Time.current.to_i + 10
      }
    }
    oauth_client = Object.new
    oauth_client.define_singleton_method(:refresh_token) do |refresh_token:|
      raise "wrong refresh token" unless refresh_token == "refresh-1"

      { "access_token" => "token-2", "expires_at" => Time.current.to_i + 3600 }
    end

    @controller.stub(:oauth_client, oauth_client) do
      token = @controller.send(:current_google_drive_access_token)

      assert_equal "token-2", token
      assert_equal "token-2", @session.dig("recording_studio_attachable_google_drive", "tokens", "access_token")
    end
  end

  def test_current_google_drive_access_token_requires_an_access_token
    error = assert_raises(RecordingStudioAttachable::Error) do
      @controller.send(:current_google_drive_access_token)
    end

    assert_equal "Connect Google Drive before importing files", error.message
  end

  def test_current_google_drive_access_token_requires_a_refresh_token_when_refresh_is_needed
    @session["recording_studio_attachable_google_drive"] = {
      "tokens" => { "access_token" => "expired", "expires_at" => Time.current.to_i }
    }

    error = assert_raises(RecordingStudioAttachable::Error) do
      @controller.send(:current_google_drive_access_token)
    end

    assert_equal "Reconnect Google Drive to continue", error.message
  end

  def test_dependency_unavailable_alert_redirects_to_attachment_upload_path
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @controller.stub(:find_recording, recording) do
      @controller.send(:dependency_unavailable_alert, RecordingStudioAttachable::DependencyUnavailableError.new("missing config"))
    end

    assert_equal "http://test.host/recordings/rec-1/attachment_upload", @response.location
  end
end
