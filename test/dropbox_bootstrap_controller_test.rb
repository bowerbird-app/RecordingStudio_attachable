# frozen_string_literal: true

require "test_helper"
require_relative "dummy/app/models/current"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/dropbox/app/controllers/recording_studio_attachable/dropbox/application_controller"
require_relative "../lib/recording_studio_attachable/dropbox/app/controllers/recording_studio_attachable/dropbox/bootstrap_controller"

class DropboxBootstrapControllerTest < ActionController::TestCase
  tests RecordingStudioAttachable::Dropbox::BootstrapController

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

    @controller = RecordingStudioAttachable::Dropbox::BootstrapController.new
    @controller.define_singleton_method(:authorize_attachment_action!) { |_action, _recording, capability_options: {}| true }
    @controller.define_singleton_method(:capability_options_for) { |_recording| {} }
    ensure_recording_lookup!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_show_returns_chooser_bootstrap_when_connected
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @request.session["recording_studio_attachable_dropbox"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
    }
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_attachment_imports_path) do |record, **_kwargs|
      "/recordings/#{record.id}/attachments/imports.json"
    end
    @controller.define_singleton_method(:recording_studio_attachable) { route_proxy }

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/dropbox/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        get :show, params: { recording_id: recording.id, format: :json }
      end
    end

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_not payload.key?("access_token")
    assert_equal "client-id", payload.fetch("client_id")
    assert_equal "dropbox", payload.fetch("provider_key")
  end

  def test_show_returns_auth_url_when_not_connected
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_attachment_imports_path) do |record, **_kwargs|
      "/recordings/#{record.id}/attachments/imports.json"
    end
    @controller.define_singleton_method(:recording_studio_attachable) { route_proxy }
    oauth_client = Object.new
    oauth_client.define_singleton_method(:authorization_url) do |**kwargs|
      raise "missing oauth state" if kwargs[:state].blank? || kwargs[:code_challenge].blank?

      "https://www.dropbox.test/auth"
    end
    @controller.define_singleton_method(:oauth_client) { oauth_client }

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/dropbox/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        get :show, params: { recording_id: recording.id, format: :json }
      end
    end

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal "https://www.dropbox.test/auth", payload.fetch("auth_url")
    assert_not payload.key?("access_token")
  end

  def test_show_returns_forbidden_when_upload_is_denied
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @controller.define_singleton_method(:authorize_attachment_action!) do |_action, _recording, capability_options: {}|
      raise RecordingStudioAttachable::Authorization::NotAuthorizedError, "Not authorized to upload attachments for Workspace"
    end

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/dropbox/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        get :show, params: { recording_id: recording.id, format: :json }
      end
    end

    assert_response :forbidden
    assert_equal "Not authorized to upload attachments for Workspace", JSON.parse(@response.body).fetch("error")
  end

  def test_show_returns_unprocessable_when_dropbox_is_disabled
    RecordingStudioAttachable.configuration.dropbox.enabled = false
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/dropbox/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        get :show, params: { recording_id: recording.id, format: :json }
      end
    end

    assert_response :unprocessable_content
    assert_equal "Dropbox addon is not enabled", JSON.parse(@response.body).fetch("error")
  end

  private

  def ensure_recording_lookup!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)
    return if RecordingStudio::Recording.respond_to?(:find)

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
  end
end
