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

  private

  def ensure_recording_lookup!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

    return if RecordingStudio::Recording.respond_to?(:find)

    RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
  end
end
