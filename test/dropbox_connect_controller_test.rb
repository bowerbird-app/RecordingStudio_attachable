# frozen_string_literal: true

require "test_helper"
require_relative "dropbox_fakes"
require_relative "dummy/app/models/current"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/dropbox/app/controllers/recording_studio_attachable/dropbox/application_controller"
require_relative "../lib/recording_studio_attachable/dropbox/app/controllers/recording_studio_attachable/dropbox/connect_controller"

class DropboxConnectControllerTest < ActionController::TestCase
  tests RecordingStudioAttachable::Dropbox::ConnectController

  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    RecordingStudioAttachable.configuration.dropbox.merge!(enabled: true)

    @controller = RecordingStudioAttachable::Dropbox::ConnectController.new
    @controller.define_singleton_method(:authorize_attachment_action!) { |_action, _recording, capability_options: {}| true }
    @controller.define_singleton_method(:capability_options_for) { |_recording| {} }
    @controller.define_singleton_method(:current_attachable_actor) { :actor }
    @controller.define_singleton_method(:dropbox_oauth_connect_path) { "/recording_studio_oauth/outbound/dropbox/connect" }
    ensure_recording_lookup!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_show_renders_oauth_connect_form_without_session_tokens
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, **kwargs|
      "/dropbox/recordings/#{record.id}/imports?#{kwargs.compact.to_query}"
    end
    route_proxy.define_singleton_method(:recording_connected_path) do |record, **kwargs|
      "/dropbox/recordings/#{record.id}/connected?#{kwargs.compact.to_query}"
    end
    @controller.define_singleton_method(:dropbox) { route_proxy }

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/connect",
            to: "recording_studio_attachable/dropbox/connect#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        DropboxFakes.with_gem_loaded do
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
    assert_includes @response.body, "/recording_studio_oauth/outbound/dropbox/connect"
    assert_includes @response.body, "true"
    assert_nil @request.session["recording_studio_attachable_dropbox"]
  end

  def test_show_uses_reconnect_when_connection_status_needs_reconnect
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, **kwargs|
      "/dropbox/recordings/#{record.id}/imports?#{kwargs.compact.to_query}"
    end
    route_proxy.define_singleton_method(:recording_connected_path) do |record, **kwargs|
      "/dropbox/recordings/#{record.id}/connected?#{kwargs.compact.to_query}"
    end
    @controller.define_singleton_method(:dropbox) { route_proxy }

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/connect",
            to: "recording_studio_attachable/dropbox/connect#show"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        DropboxFakes.with_gem_loaded do
          RecordingStudioAttachable::Dropbox::Integration.stub(:connection_status, :needs_reconnect) do
            @controller.stub(:render, lambda { |*_, **kwargs|
              @controller.response_body = [@controller.instance_variable_get(:@reconnect).to_s]
              @controller.status = kwargs[:status] || :ok
            }) do
              get :show, params: { recording_id: recording.id }
            end
          end
        end
      end
    end

    assert_response :success
    assert_equal "true", @response.body
  end

  def test_complete_renders_provider_auth_complete_without_session_tokens
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

    with_routing do |set|
      set.draw do
        get "/dropbox/recordings/:recording_id/connected",
            to: "recording_studio_attachable/dropbox/connect#complete"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        DropboxFakes.with_gem_loaded do
          @controller.define_singleton_method(:dropbox) do
            Object.new.tap do |proxy|
              proxy.define_singleton_method(:recording_imports_path) do |record, **kwargs|
                "/dropbox/recordings/#{record.id}/imports?#{kwargs.compact.to_query}"
              end
            end
          end
          get :complete, params: { recording_id: recording.id, popup: 1, provider_key: "dropbox" }
        end
      end
    end

    assert_response :success
    assert_includes @response.body, "provider-auth-complete"
    assert_includes @response.body, "dropbox"
    assert_includes @response.body, "reloadUrl"
    assert_includes @response.body, "/dropbox/recordings/rec-1/imports"
    assert_includes @response.body, "embed=modal"
    assert_includes @response.body, "window.close()"
    assert_nil @request.session["recording_studio_attachable_dropbox"]
  end

  def test_destroy_disconnects_through_oauth_and_redirects_to_the_documented_route
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, options = {}|
      suffix = options.compact.to_query
      path = "/dropbox/recordings/#{record.id}/imports"
      suffix.present? ? "#{path}?#{suffix}" : path
    end
    @controller.define_singleton_method(:dropbox) { route_proxy }
    @controller.define_singleton_method(:dropbox_oauth_disconnect_path) do |connection_id|
      "/recording_studio_oauth/outbound/connections/#{connection_id}?return_to=%2Fdropbox%2Frecordings%2Frec-1%2Fimports"
    end

    with_routing do |set|
      set.draw do
        delete "/dropbox/recordings/:recording_id/connect",
               to: "recording_studio_attachable/dropbox/connect#destroy"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        DropboxFakes.with_gem_loaded do
          RecordingStudioAttachable::Dropbox::Integration.stub(:connection_id_for, "conn-1") do
            @controller.stub(:protect_against_forgery?, false) do
              delete :destroy, params: { recording_id: recording.id, redirect_mode: "return_to", return_to: "/pages/page-1" }
            end
          end
        end
      end
    end

    assert_response :temporary_redirect
    assert_redirected_to "/recording_studio_oauth/outbound/connections/conn-1?return_to=%2Fdropbox%2Frecordings%2Frec-1%2Fimports"
    assert_nil flash[:notice]
  end

  def test_destroy_flashes_failure_when_there_is_no_connection_to_disconnect
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, options = {}|
      suffix = options.compact.to_query
      path = "/dropbox/recordings/#{record.id}/imports"
      suffix.present? ? "#{path}?#{suffix}" : path
    end
    @controller.define_singleton_method(:dropbox) { route_proxy }

    with_routing do |set|
      set.draw do
        delete "/dropbox/recordings/:recording_id/connect",
               to: "recording_studio_attachable/dropbox/connect#destroy"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        DropboxFakes.with_gem_loaded do
          RecordingStudioAttachable::Dropbox::Integration.stub(:connection_id_for, nil) do
            @controller.stub(:protect_against_forgery?, false) do
              delete :destroy, params: { recording_id: recording.id }
            end
          end
        end
      end
    end

    assert_redirected_to "/dropbox/recordings/rec-1/imports"
    assert_equal "Dropbox isn't connected.", flash[:alert]
    assert_nil flash[:notice]
  end

  def test_destroy_returns_forbidden_when_upload_is_denied
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @controller.define_singleton_method(:authorize_attachment_action!) do |_action, _recording, capability_options: {}|
      raise RecordingStudioAttachable::Authorization::NotAuthorizedError, "Not authorized to upload attachments for Workspace"
    end

    with_routing do |set|
      set.draw do
        delete "/dropbox/recordings/:recording_id/connect",
               to: "recording_studio_attachable/dropbox/connect#destroy"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        DropboxFakes.with_gem_loaded do
          @controller.stub(:protect_against_forgery?, false) do
            delete :destroy, params: { recording_id: recording.id, format: :json }
          end
        end
      end
    end

    assert_response :forbidden
    assert_equal "Not authorized to upload attachments for Workspace", JSON.parse(@response.body).fetch("error")
  end

  private

  def ensure_recording_lookup!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

    return if RecordingStudio::Recording.respond_to?(:find)

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
  end
end
