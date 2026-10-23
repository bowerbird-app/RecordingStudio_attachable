# frozen_string_literal: true

require "test_helper"
require_relative "dropbox_fakes"
require_relative "dummy/app/models/current"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/dropbox/app/controllers/recording_studio_attachable/dropbox/application_controller"
require_relative "../lib/recording_studio_attachable/dropbox/app/controllers/recording_studio_attachable/dropbox/bootstrap_controller"

class DropboxBootstrapControllerTest < ActionController::TestCase
  tests RecordingStudioAttachable::Dropbox::BootstrapController

  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    RecordingStudioAttachable.configuration.dropbox.merge!(
      enabled: true,
      client_id: "client-id"
    )

    @controller = RecordingStudioAttachable::Dropbox::BootstrapController.new
    @controller.define_singleton_method(:authorize_attachment_action!) { |_action, _recording, capability_options: {}| true }
    @controller.define_singleton_method(:capability_options_for) { |_recording| {} }
    @controller.define_singleton_method(:current_attachable_actor) { :actor }
    ensure_recording_lookup!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_show_returns_chooser_bootstrap_when_connected
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, **_kwargs|
      "/dropbox/recordings/#{record.id}/imports.json"
    end
    @controller.define_singleton_method(:dropbox) { route_proxy }

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/dropbox/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        DropboxFakes.with_gem_loaded do
          RecordingStudioAttachable::Dropbox::Integration.stub(:chooser_access, "token-1") do
            get :show, params: { recording_id: recording.id, format: :json }
          end
        end
      end
    end

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal "client-id", payload.fetch("client_id")
    assert_equal "dropbox", payload.fetch("provider_key")
    assert_equal "/dropbox/recordings/rec-1/imports.json", payload.fetch("import_url")
    assert_not payload.key?("access_token")
    assert_nil @request.session["recording_studio_attachable_dropbox"]
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
        DropboxFakes.with_gem_loaded do
          get :show, params: { recording_id: recording.id, format: :json }
        end
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
    assert_equal "Dropbox isn't available right now", JSON.parse(@response.body).fetch("error")
  end

  def test_show_returns_direct_oauth_connect_payload_when_reconnect_is_required
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, **_kwargs|
      "/dropbox/recordings/#{record.id}/imports.json"
    end
    route_proxy.define_singleton_method(:recording_connected_path) do |record, **kwargs|
      "/dropbox/recordings/#{record.id}/connected?#{kwargs.compact.to_query}"
    end
    @controller.define_singleton_method(:dropbox) { route_proxy }
    @controller.define_singleton_method(:recording_connect_path) do |_record, **kwargs|
      "/dropbox/recordings/rec-1/connect?#{kwargs.compact.to_query}"
    end
    @controller.define_singleton_method(:dropbox_oauth_connect_path) { "/recording_studio_oauth/outbound/dropbox/connect" }
    @controller.define_singleton_method(:form_authenticity_token) { "csrf-token" }

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/dropbox/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        DropboxFakes.with_gem_loaded do
          RecordingStudioAttachable::Dropbox::Integration.stub(:chooser_access, ->(*) { raise StandardError, "reconnect" }) do
            RecordingStudioAttachable::Dropbox::Integration.stub(:reconnect_required?, true) do
              get :show, params: { recording_id: recording.id, format: :json }
            end
          end
        end
      end
    end

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_includes payload.fetch("connect_url"), "/dropbox/recordings/rec-1/connect"
    assert_includes payload.fetch("connect_url"), "popup=1"
    assert_equal "/recording_studio_oauth/outbound/dropbox/connect", payload.fetch("oauth_connect_url")
    assert_includes payload.fetch("return_to"), "/dropbox/recordings/rec-1/connected"
    assert_includes payload.fetch("return_to"), "popup=1"
    assert_equal "csrf-token", payload.fetch("authenticity_token")
  end

  def test_show_preserves_attachment_redirect_params_in_import_url
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, **kwargs|
      suffix = kwargs.compact.to_query
      "/dropbox/recordings/#{record.id}/imports#{"?#{suffix}" if suffix.present?}"
    end
    @controller.define_singleton_method(:dropbox) { route_proxy }

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/bootstrap(.:format)",
            to: "recording_studio_attachable/dropbox/bootstrap#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        DropboxFakes.with_gem_loaded do
          RecordingStudioAttachable::Dropbox::Integration.stub(:chooser_access, "token-1") do
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
    assert_nil @request.session["recording_studio_attachable_dropbox"]
  end

  private

  def ensure_recording_lookup!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

    return if RecordingStudio::Recording.respond_to?(:find)

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
  end
end
