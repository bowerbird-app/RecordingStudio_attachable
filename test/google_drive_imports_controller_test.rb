# frozen_string_literal: true

require "test_helper"
require_relative "google_drive_fakes"
require_relative "dummy/app/models/current"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/application_controller"
require_relative "../lib/recording_studio_attachable/google_drive/app/controllers/recording_studio_attachable/google_drive/imports_controller"
require_relative "../lib/recording_studio_attachable/services/base_service"

class GoogleDriveImportsControllerTest < ActionController::TestCase
  tests RecordingStudioAttachable::GoogleDrive::ImportsController

  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)
  FakeRequestError = Class.new(StandardError)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    RecordingStudioAttachable.configuration.google_drive.merge!(enabled: true, page_size: 25)

    @controller = RecordingStudioAttachable::GoogleDrive::ImportsController.new
    @controller.define_singleton_method(:authorize_attachment_action!) { |_action, _recording, capability_options: {}| true }
    @controller.define_singleton_method(:capability_options_for) { |_recording| {} }
    @controller.define_singleton_method(:current_attachable_actor) { :actor }
    @controller.define_singleton_method(:current_attachable_impersonator) { :impersonator }
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

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
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
    end

    assert_redirected_to "/recording_studio_attachable/recordings/rec-1/attachments"
    assert_equal recording, captured[:parent_recording]
    assert_equal %w[file-1 file-2], captured[:file_ids]
    assert_nil captured[:access_token]
    assert_equal :actor, captured[:actor]
    assert_nil @request.session["recording_studio_attachable_google_drive"]
  end

  def test_create_renders_modal_event_when_embedded_provider_import_succeeds
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [Object.new])
    attachable_proxy = Object.new
    attachable_proxy.define_singleton_method(:recording_attachments_path) do |record|
      "/recording_studio_attachable/recordings/#{record.id}/attachments"
    end
    @controller.define_singleton_method(:recording_studio_attachable) { attachable_proxy }

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
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

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports(.:format)",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.stub(:call, result) do
            @controller.stub(:protect_against_forgery?, false) do
              post :create, params: { recording_id: recording.id, file_ids: ["file-1"], format: :json }
            end
          end
        end
      end
    end

    assert_response :created
    assert_equal "/recording_studio_attachable/recordings/rec-1/attachments", JSON.parse(@response.body).fetch("redirect_path")
    assert_nil @request.session["recording_studio_attachable_google_drive"]
  end

  def test_create_uses_explicit_return_to_for_provider_redirects
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [Object.new])
    attachable_proxy = Object.new
    attachable_proxy.define_singleton_method(:recording_attachments_path) { |record| "/recording_studio_attachable/recordings/#{record.id}/attachments" }
    @controller.define_singleton_method(:recording_studio_attachable) { attachable_proxy }

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports(.:format)",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
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
    end

    assert_response :created
    assert_equal "/pages/page-1#gallery", JSON.parse(@response.body).fetch("redirect_path")
  end

  def test_index_lists_drive_files_when_connected
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    page = GoogleDriveFakes::Page.new(
      entries: [
        GoogleDriveFakes::DriveFile.new(id: "file-1", name: "Brief.pdf", mime_type: "application/pdf", web_view_link: "https://drive.test/file-1"),
        GoogleDriveFakes::DriveFile.new(id: "folder-1", name: "Inbox", mime_type: "application/vnd.google-apps.folder", folder: true)
      ],
      next_cursor: "next-page"
    )
    client = Object.new
    client.define_singleton_method(:list) { |**| page }

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/imports",
            to: "recording_studio_attachable/google_drive/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Integration.stub(:connection, GoogleDriveFakes::Connection.new(access_token: "tok")) do
            @controller.stub(:google_drive_client, client) do
              @controller.stub(:render, lambda { |*_, **kwargs|
                files = @controller.instance_variable_get(:@files)
                token = @controller.instance_variable_get(:@next_page_token)
                @controller.response_body = ["#{files.map { |file| file['id'] }.join(',')} #{token}"]
                @controller.status = kwargs[:status] || :ok
              }) do
                get :index, params: { recording_id: recording.id }
              end
            end
          end
        end
      end
    end

    assert_response :success
    assert_equal "file-1 next-page", @response.body
    assert_nil @request.session["recording_studio_attachable_google_drive"]
  end

  def test_index_lists_the_next_drive_page_when_page_token_is_present
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    page = GoogleDriveFakes::Page.new(
      entries: [
        GoogleDriveFakes::DriveFile.new(id: "file-2", name: "Notes.pdf", mime_type: "application/pdf", web_view_link: "https://drive.test/file-2")
      ],
      next_cursor: nil
    )
    captured = nil
    client = Object.new
    client.define_singleton_method(:list) do |**kwargs|
      captured = kwargs
      page
    end

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/imports",
            to: "recording_studio_attachable/google_drive/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Integration.stub(:connection, GoogleDriveFakes::Connection.new(access_token: "tok")) do
            @controller.stub(:google_drive_client, client) do
              @controller.stub(:render, lambda { |*_, **kwargs|
                files = @controller.instance_variable_get(:@files)
                token = @controller.instance_variable_get(:@next_page_token)
                @controller.response_body = ["#{files.map { |file| file['id'] }.join(',')} #{token}"]
                @controller.status = kwargs[:status] || :ok
              }) do
                get :index, params: { recording_id: recording.id, page_token: "next-page" }
              end
            end
          end
        end
      end
    end

    assert_response :success
    assert_equal "next-page", captured[:cursor]
    assert_equal 25, captured[:page_size]
    assert_equal "file-2 ", @response.body
  end

  def test_index_renders_connect_state_when_there_is_no_connection
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @controller.define_singleton_method(:google_drive_oauth_connect_path) { "/recording_studio_oauth/outbound/google_drive/connect" }
    @controller.define_singleton_method(:google_drive) do
      Object.new.tap do |proxy|
        proxy.define_singleton_method(:recording_imports_path) do |record, **kwargs|
          "/google_drive/recordings/#{record.id}/imports?#{kwargs.compact.to_query}"
        end
        proxy.define_singleton_method(:recording_connected_path) do |record, **kwargs|
          "/google_drive/recordings/#{record.id}/connected?#{kwargs.compact.to_query}"
        end
      end
    end

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/imports",
            to: "recording_studio_attachable/google_drive/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Integration.stub(:connection, nil) do
            @controller.stub(:render, lambda { |*_, **kwargs|
              @controller.response_body = [@controller.instance_variable_get(:@oauth_connect_path).to_s]
              @controller.status = kwargs[:status] || :ok
            }) do
              get :index, params: { recording_id: recording.id, redirect_mode: "return_to", return_to: "/pages/page-1" }
            end
          end
        end
      end
    end

    assert_response :success
    assert_includes @response.body, "/recording_studio_oauth/outbound/google_drive/connect"
    assert_nil @request.session["recording_studio_attachable_google_drive"]
  end

  def test_index_renders_reconnect_when_the_google_drive_gem_requires_reconnect
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @controller.define_singleton_method(:google_drive_oauth_connect_path) { "/recording_studio_oauth/outbound/google_drive/connect" }
    @controller.define_singleton_method(:google_drive) do
      Object.new.tap do |proxy|
        proxy.define_singleton_method(:recording_imports_path) do |record, **kwargs|
          "/google_drive/recordings/#{record.id}/imports?#{kwargs.compact.to_query}"
        end
        proxy.define_singleton_method(:recording_connected_path) do |record, **kwargs|
          "/google_drive/recordings/#{record.id}/connected?#{kwargs.compact.to_query}"
        end
      end
    end
    client = Object.new
    client.define_singleton_method(:list) { |**| raise RecordingStudioGoogleDrive::ReconnectRequired, "Reconnect Google Drive" }

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/imports",
            to: "recording_studio_attachable/google_drive/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Integration.stub(:connection, GoogleDriveFakes::Connection.new(access_token: "tok")) do
            @controller.stub(:google_drive_client, client) do
              @controller.stub(:render, lambda { |*_, **kwargs|
                @controller.response_body = [
                  [@controller.instance_variable_get(:@reconnect), @controller.instance_variable_get(:@oauth_connect_path)].join(" ")
                ]
                @controller.status = kwargs[:status] || :ok
              }) do
                get :index, params: { recording_id: recording.id }
              end
            end
          end
        end
      end
    end

    assert_response :success
    assert_includes @response.body, "true"
    assert_includes @response.body, "/recording_studio_oauth/outbound/google_drive/connect"
    assert_nil @request.session["recording_studio_attachable_google_drive"]
  end

  def test_index_renders_bad_gateway_when_google_drive_returns_an_error
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    client = Object.new
    client.define_singleton_method(:list) { |**| raise FakeRequestError, "drive down" }

    with_routing do |set|
      set.draw do
        get "/google_drive/recordings/:recording_id/imports",
            to: "recording_studio_attachable/google_drive/imports#index"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Integration.stub(:connection, GoogleDriveFakes::Connection.new(access_token: "tok")) do
            RecordingStudioAttachable::GoogleDrive::Integration.stub(:reconnect_required?, false) do
              RecordingStudioAttachable::GoogleDrive::Integration.stub(:request_error?, true) do
                @controller.stub(:google_drive_client, client) do
                  @controller.stub(:render, lambda { |*_, **kwargs|
                    @controller.response_body = [Array(@controller.flash.now[:alert]).join]
                    @controller.status = kwargs[:status] || :ok
                  }) do
                    get :index, params: { recording_id: recording.id }
                  end
                end
              end
            end
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

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports(.:format)",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.stub(:call, result) do
            @controller.stub(:protect_against_forgery?, false) do
              post :create, params: { recording_id: recording.id, file_ids: [], format: :json }
            end
          end
        end
      end
    end

    assert_response :unprocessable_entity
    assert_equal({ "error" => "Select at least one file" }, JSON.parse(@response.body))
  end

  def test_create_preserves_picker_resource_keys_when_forwarding_selected_files
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [Object.new])
    captured = nil
    attachable_proxy = Object.new
    attachable_proxy.define_singleton_method(:recording_attachments_path) do |record|
      "/recording_studio_attachable/recordings/#{record.id}/attachments"
    end
    @controller.define_singleton_method(:recording_studio_attachable) { attachable_proxy }

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports(.:format)",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.stub(:call, lambda { |**kwargs|
            captured = kwargs
            result
          }) do
            @controller.stub(:protect_against_forgery?, false) do
              post :create, params: {
                recording_id: recording.id,
                file_ids: [{ id: "file-1", resource_key: "resource-key-1" }],
                format: :json
              }
            end
          end
        end
      end
    end

    assert_response :created
    assert_equal [{ "id" => "file-1", "resource_key" => "resource-key-1" }], captured[:file_ids]
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
    assert_equal "Google Drive isn't available right now", JSON.parse(@response.body).fetch("error")
  end

  def test_index_redirects_back_to_upload_page_when_google_drive_is_misconfigured
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    RecordingStudioAttachable.configuration.google_drive.enabled = false
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
    assert_equal "Google Drive isn't available right now", flash[:alert]
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

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.stub(:call, result) do
            @controller.stub(:protect_against_forgery?, false) do
              post :create, params: { recording_id: recording.id, file_ids: [] }
            end
          end
        end
      end
    end

    assert_redirected_to "/google_drive/recordings/rec-1/imports"
    assert_equal "Select at least one file", flash[:alert]
  end

  def test_create_returns_json_unauthorized_when_reconnect_is_required
    recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
    @controller.define_singleton_method(:recording_connect_path) do |record, **kwargs|
      "/google_drive/recordings/#{record.id}/connect?#{kwargs.compact.to_query}"
    end

    with_routing do |set|
      set.draw do
        post "/google_drive/recordings/:recording_id/imports(.:format)",
             to: "recording_studio_attachable/google_drive/imports#create"
      end

      @routes = set

      RecordingStudio::Recording.stub(:find, recording) do
        GoogleDriveFakes.with_gem_loaded do
          RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.stub(:call, ->(**) { raise RecordingStudioGoogleDrive::ReconnectRequired, "Reconnect Google Drive" }) do
            @controller.stub(:protect_against_forgery?, false) do
              post :create, params: { recording_id: recording.id, file_ids: ["file-1"], format: :json }
            end
          end
        end
      end
    end

    assert_response :unauthorized
    payload = JSON.parse(@response.body)
    assert_equal "Reconnect Google Drive to continue", payload.fetch("error")
    assert_includes payload.fetch("connect_url"), "/google_drive/recordings/rec-1/connect"
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
