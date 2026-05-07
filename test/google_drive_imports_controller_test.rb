# frozen_string_literal: true

require "test_helper"
require_relative "dummy/app/models/current"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/imports_controller"
require_relative "../lib/recording_studio_attachable/services/base_service"

class GoogleDriveImportsControllerTest < ActionController::TestCase
  tests RecordingStudioAttachable::GoogleDrive::ImportsController

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

    @controller = RecordingStudioAttachable::GoogleDrive::ImportsController.new
    @controller.define_singleton_method(:authorize_attachment_action!) { |_action, _recording, capability_options: {}| true }
    @controller.define_singleton_method(:capability_options_for) { |_recording| {} }
    ensure_recording_lookup!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_create_imports_selected_drive_files_through_the_public_service_layer
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [Object.new])
    captured = nil
    attachable_proxy = Object.new
    attachable_proxy.define_singleton_method(:recording_attachments_path) do |record|
      "/recording_studio_attachable/recordings/#{record.id}/attachments"
    end
    @controller.define_singleton_method(:recording_studio_attachable) { attachable_proxy }
    @request.session["recording_studio_attachable_google_drive"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
    }

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.stub(:call, lambda { |**kwargs|
          captured = kwargs
          result
        }) do
          @controller.stub(:protect_against_forgery?, false) do
            post :create, params: { recording_id: recording.id, file_ids: %w[file-1 file-2] }
          end
        end
      end
    end

    assert_redirected_to "/recording_studio_attachable/recordings/rec-1/attachments"
    assert_equal recording, captured[:parent_recording]
    assert_equal %w[file-1 file-2], captured[:file_ids]
    assert_equal "token-1", captured[:access_token]
  end

  def test_create_renders_modal_event_when_embedded_provider_import_succeeds
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [Object.new])
    attachable_proxy = Object.new
    attachable_proxy.define_singleton_method(:recording_attachments_path) do |record|
      "/recording_studio_attachable/recordings/#{record.id}/attachments"
    end
    @controller.define_singleton_method(:recording_studio_attachable) { attachable_proxy }
    @request.session["recording_studio_attachable_google_drive"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
    }

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.stub(:call, result) do
          @controller.stub(:protect_against_forgery?, false) do
            post :create, params: {
              recording_id: recording.id,
              file_ids: ["file-1"],
              embed: "modal",
              provider_key: "google_drive",
              provider_modal_id: "modal-1"
            }
          end
        end
      end
    end

    assert_response :success
    assert_includes @response.body, "provider-import-complete"
    assert_includes @response.body, "modal-1"
    assert_includes @response.body, "/recording_studio_attachable/recordings/rec-1/attachments"
  end

  def test_create_returns_json_for_client_picker_imports
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [Object.new])
    attachable_proxy = Object.new
    attachable_proxy.define_singleton_method(:recording_attachments_path) do |record|
      "/recording_studio_attachable/recordings/#{record.id}/attachments"
    end
    @controller.define_singleton_method(:recording_studio_attachable) { attachable_proxy }
    @request.session["recording_studio_attachable_google_drive"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
    }

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports(.:format)",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.stub(:call, result) do
          @controller.stub(:protect_against_forgery?, false) do
            post :create, params: { recording_id: recording.id, file_ids: ["file-1"], format: :json }
          end
        end
      end
    end

    assert_response :created
    assert_equal "/recording_studio_attachable/recordings/rec-1/attachments", JSON.parse(@response.body).fetch("redirect_path")
  end

  def test_create_uses_explicit_return_to_for_provider_redirects
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [Object.new])
    attachable_proxy = Object.new
    attachable_proxy.define_singleton_method(:recording_attachments_path) { |record| "/recording_studio_attachable/recordings/#{record.id}/attachments" }
    @controller.define_singleton_method(:recording_studio_attachable) { attachable_proxy }
    @request.session["recording_studio_attachable_google_drive"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
    }

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports(.:format)",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.stub(:call, result) do
          @controller.stub(:protect_against_forgery?, false) do
            post :create, params: {
              recording_id: recording.id,
              file_ids: ["file-1"],
              redirect_mode: "return_to",
              return_to: "/pages/page-1#gallery",
              format: :json
            }
          end
        end
      end
    end

    assert_response :created
    assert_equal "/pages/page-1#gallery", JSON.parse(@response.body).fetch("redirect_path")
  end

  def test_index_renders_disconnected_state_when_tokens_are_missing
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_connect_path) do |record, options = {}|
      suffix = options.compact.to_query
      path = "/google_drive/recordings/#{record.id}/connect"
      suffix.present? ? "#{path}?#{suffix}" : path
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/imports",
            to: "recording_studio_attachable/google_drive/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        @controller.stub(:render, lambda { |*_, **kwargs|
          @controller.response_body = [@controller.instance_variable_get(:@authorization_path).to_s]
          @controller.status = kwargs[:status] || :ok
        }) do
          get :index, params: { recording_id: recording.id, redirect_mode: "return_to", return_to: "/pages/page-1" }
        end
      end
    end

    assert_response :success
    assert_includes @response.body, "/google_drive/recordings/rec-1/connect"
    assert_includes @response.body, "return_to=%2Fpages%2Fpage-1"
  end

  def test_index_redirects_to_reconnect_when_google_drive_session_is_unauthorized
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, options = {}|
      suffix = options.compact.to_query
      path = "/google_drive/recordings/#{record.id}/imports"
      suffix.present? ? "#{path}?#{suffix}" : path
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }
    @request.session["recording_studio_attachable_google_drive"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
    }
    client = Object.new
    client.define_singleton_method(:list_files) do |**|
      raise RecordingStudioAttachable::GoogleDrive::Client::UnauthorizedError, "expired"
    end

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/imports",
            to: "recording_studio_attachable/google_drive/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        @controller.stub(:google_drive_client, client) do
          get :index, params: { recording_id: recording.id, redirect_mode: "return_to", return_to: "/pages/page-1" }
        end
      end
    end

    assert_redirected_to "/google_drive/recordings/rec-1/imports?redirect_mode=return_to&return_to=%2Fpages%2Fpage-1"
    assert_equal "Google Drive session expired. Reconnect to continue.", flash[:alert]
    assert_nil @request.session.dig("recording_studio_attachable_google_drive", "tokens")
  end

  def test_index_renders_bad_gateway_when_google_drive_returns_an_error
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @request.session["recording_studio_attachable_google_drive"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
    }
    client = Object.new
    client.define_singleton_method(:list_files) do |**|
      raise RecordingStudioAttachable::GoogleDrive::Client::Error, "drive down"
    end

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/imports",
            to: "recording_studio_attachable/google_drive/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        @controller.stub(:google_drive_client, client) do
          @controller.stub(:render, lambda { |*_, **kwargs|
            @controller.response_body = [Array(@controller.flash.now[:alert]).join]
            @controller.status = kwargs[:status] || :ok
          }) do
            get :index, params: { recording_id: recording.id, query: "budget" }
          end
        end
      end
    end

    assert_response :bad_gateway
    assert_includes @response.body, "drive down"
  end

  def test_create_returns_json_error_when_the_import_service_fails
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: "Select at least one file")
    @request.session["recording_studio_attachable_google_drive"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
    }

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports(.:format)",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.stub(:call, result) do
          @controller.stub(:protect_against_forgery?, false) do
            post :create, params: { recording_id: recording.id, file_ids: [], format: :json }
          end
        end
      end
    end

    assert_response :unprocessable_entity
    assert_equal({ "error" => "Select at least one file" }, JSON.parse(@response.body))
  end

  def test_create_returns_json_error_when_google_drive_is_not_configured
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    RecordingStudioAttachable.configuration.google_drive.enabled = false

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports(.:format)",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        @controller.stub(:protect_against_forgery?, false) do
          post :create, params: { recording_id: recording.id, file_ids: ["file-1"], format: :json }
        end
      end
    end

    assert_response :unprocessable_entity
    assert_equal "Google Drive addon is not enabled", JSON.parse(@response.body).fetch("error")
  end

  def test_index_redirects_back_to_upload_page_when_google_drive_is_misconfigured
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    RecordingStudioAttachable.configuration.google_drive.client_id = nil
    upload_proxy = Object.new
    upload_proxy.define_singleton_method(:recording_attachment_upload_path) do |record, options = {}|
      suffix = options.compact.to_query
      path = "/recordings/#{record.id}/attachments/upload"
      suffix.present? ? "#{path}?#{suffix}" : path
    end
    @controller.define_singleton_method(:recording_studio_attachable) { upload_proxy }

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/imports",
            to: "recording_studio_attachable/google_drive/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        get :index, params: { recording_id: recording.id, redirect_mode: "return_to", return_to: "/pages/page-1" }
      end
    end

    assert_redirected_to "/recordings/rec-1/attachments/upload?redirect_mode=return_to&return_to=%2Fpages%2Fpage-1"
    assert_equal "Google Drive addon is missing client credentials or redirect URI", flash[:alert]
  end

  def test_create_redirects_back_to_imports_when_html_import_service_fails
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: "Select at least one file")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, options = {}|
      suffix = options.compact.to_query
      path = "/google_drive/recordings/#{record.id}/imports"
      suffix.present? ? "#{path}?#{suffix}" : path
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }
    @request.session["recording_studio_attachable_google_drive"] = {
      "tokens" => { "access_token" => "token-1", "expires_at" => Time.current.to_i + 3600 }
    }

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.stub(:call, result) do
          @controller.stub(:protect_against_forgery?, false) do
            post :create, params: { recording_id: recording.id, file_ids: [] }
          end
        end
      end
    end

    assert_redirected_to "/google_drive/recordings/rec-1/imports"
    assert_equal "Select at least one file", flash[:alert]
  end

  def test_create_redirects_back_to_imports_when_html_session_has_expired
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, options = {}|
      suffix = options.compact.to_query
      path = "/google_drive/recordings/#{record.id}/imports"
      suffix.present? ? "#{path}?#{suffix}" : path
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }
    @request.session["recording_studio_attachable_google_drive"] = {
      "tokens" => {
        "access_token" => "expired-token",
        "refresh_token" => "refresh-token",
        "expires_at" => Time.current.to_i + 5
      }
    }
    oauth_client = Object.new
    oauth_client.define_singleton_method(:refresh_token) do |refresh_token:|
      raise "wrong refresh token" unless refresh_token == "refresh-token"

      raise RecordingStudioAttachable::GoogleDrive::Client::UnauthorizedError, "expired"
    end

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        @controller.stub(:oauth_client, oauth_client) do
          @controller.stub(:protect_against_forgery?, false) do
            post :create, params: { recording_id: recording.id, file_ids: ["file-1"] }
          end
        end
      end
    end

    assert_redirected_to "/google_drive/recordings/rec-1/imports"
    assert_equal "Google Drive session expired. Reconnect to continue.", flash[:alert]
  end

  def test_create_returns_json_unauthorized_when_the_google_session_has_expired
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    route_proxy = Object.new
    route_proxy.define_singleton_method(:recording_imports_path) do |record, **kwargs|
      suffix = kwargs.compact.to_query
      path = "/google_drive/recordings/#{record.id}/imports"
      suffix.present? ? "#{path}?#{suffix}" : path
    end
    @controller.define_singleton_method(:google_drive) { route_proxy }
    @request.session["recording_studio_attachable_google_drive"] = {
      "tokens" => {
        "access_token" => "expired-token",
        "refresh_token" => "refresh-token",
        "expires_at" => Time.current.to_i + 5
      }
    }
    oauth_client = Object.new
    oauth_client.define_singleton_method(:refresh_token) do |refresh_token:|
      raise "wrong refresh token" unless refresh_token == "refresh-token"

      raise RecordingStudioAttachable::GoogleDrive::Client::UnauthorizedError, "expired"
    end

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports(.:format)",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        @controller.stub(:oauth_client, oauth_client) do
          @controller.stub(:protect_against_forgery?, false) do
            post :create, params: { recording_id: recording.id, file_ids: ["file-1"], format: :json }
          end
        end
      end
    end

    assert_response :unauthorized
    assert_equal "Google Drive session expired. Reconnect to continue.", JSON.parse(@response.body).fetch("error")
    assert_nil @request.session.dig("recording_studio_attachable_google_drive", "tokens")
  end

  private

  def ensure_recording_lookup!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

    return if RecordingStudio::Recording.respond_to?(:find)

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
  end
end
