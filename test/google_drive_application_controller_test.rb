# frozen_string_literal: true

require "test_helper"
require_relative "google_drive_fakes"
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

  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    @controller = ProbeController.new
    @request = ActionDispatch::TestRequest.create
    @response = ActionDispatch::TestResponse.create
    @request.env["action_dispatch.request.flash_hash"] = ActionDispatch::Flash::FlashHash.new
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

    assert_equal "Google Drive isn't available right now", error.message
  end

  def test_ensure_google_drive_enabled_requires_the_google_drive_gem
    RecordingStudioAttachable.configuration[:google_drive] = { enabled: true }

    error = assert_raises(RecordingStudioAttachable::DependencyUnavailableError) do
      RecordingStudioAttachable::GoogleDrive::Integration.stub(:gem_loaded?, false) do
        @controller.send(:ensure_google_drive_enabled!)
      end
    end

    assert_equal "Google Drive isn't available right now", error.message
  end

  def test_ensure_google_drive_picker_configured_requires_picker_keys
    RecordingStudioAttachable.configuration[:google_drive] = { enabled: true }

    error = assert_raises(RecordingStudioAttachable::DependencyUnavailableError) do
      @controller.send(:ensure_google_drive_picker_configured!)
    end

    assert_equal "Google Drive picker needs an API key and app id", error.message
  end

  def test_ensure_google_drive_picker_configured_rejects_dummy_placeholder_picker_values
    RecordingStudioAttachable.configuration[:google_drive] = {
      enabled: true,
      api_key: "dummy-google-drive-api-key",
      app_id: "dummy-google-drive-app-id"
    }

    error = assert_raises(RecordingStudioAttachable::DependencyUnavailableError) do
      @controller.send(:ensure_google_drive_picker_configured!)
    end

    assert_equal "Google Drive picker needs an API key and app id", error.message
  end

  def test_google_drive_connected_uses_oauth_connection_not_session
    @controller.instance_variable_set(:@recording, FakeRecording.new(id: "rec-1", recordable_type: "Workspace"))

    RecordingStudioAttachable::GoogleDrive::Integration.stub(:connection, nil) do
      assert_not @controller.send(:google_drive_connected?)
    end

    connection = GoogleDriveFakes::Connection.new(access_token: "token-1")
    RecordingStudioAttachable::GoogleDrive::Integration.stub(:connection, connection) do
      assert @controller.send(:google_drive_connected?)
    end

    assert_nil @session["recording_studio_attachable_google_drive"]
  end

  def test_dependency_unavailable_alert_redirects_to_attachment_upload_path
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @controller.stub(:find_recording, recording) do
      @controller.send(:dependency_unavailable_alert, RecordingStudioAttachable::DependencyUnavailableError.new("missing config"))
    end

    assert_equal "http://test.host/recordings/rec-1/attachment_upload", @response.location
  end
end
