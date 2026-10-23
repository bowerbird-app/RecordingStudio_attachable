# frozen_string_literal: true

require "tempfile"

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/attachment_imports_controller"
require_relative "../lib/recording_studio_attachable/services/base_service"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../app/services/recording_studio_attachable/services/import_attachment_payloads"
require_relative "../app/services/recording_studio_attachable/services/record_attachment_uploads"

module RecordingStudioAttachable
  class AttachmentImportsControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)

    def setup
      ensure_recording_lookup!
    end

    def test_create_normalizes_provider_blob_payloads_for_batch_finalize
      @controller = AttachmentImportsController.new
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
      captured = nil
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [])
      provider = Struct.new(:key).new(:google_drive)

      with_routing do |set|
        set.draw do
          post "/recordings/:recording_id/attachments/imports",
               to: "recording_studio_attachable/attachment_imports#create"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              @controller.define_singleton_method(:recording_attachments_path) { |_recording| "/recordings/#{recording.id}/attachments" }

              RecordingStudioAttachable.configuration.stub(:upload_provider, provider) do
                RecordingStudioAttachable::Services::ImportAttachmentPayloads.stub(:call, lambda { |**kwargs|
                  captured = kwargs
                  result
                }) do
                  @controller.stub(:protect_against_forgery?, false) do
                    post :create,
                         params: {
                           recording_id: recording.id,
                           attachment_import: {
                             provider_key: "google_drive",
                             attachments: [
                               {
                                 signed_blob_id: "blob-1",
                                 name: "Drive file",
                                 metadata: { external_id: "file-1", provider: "spoofed" },
                                 source: "spoofed",
                                 service_name: "mirror"
                               }
                             ]
                           }
                         },
                         as: :json
                  end
                end
              end
            end
          end
        end
      end

      assert_response :created
      assert_equal recording, captured[:parent_recording]
      assert_equal [{ provider_key: "google_drive", signed_blob_id: "blob-1", name: "Drive file", metadata: { "external_id" => "file-1", "provider" => "google_drive" }, provider_payload: nil }],
                   captured[:attachments]
    end

    def test_attachment_payloads_normalize_uploaded_files_for_import_service
      @controller = AttachmentImportsController.new
      uploaded_file, tempfile = uploaded_svg_file
      provider = Struct.new(:key).new(:demo_cloud)

      @controller.send(
        :params=,
        ActionController::Parameters.new(
          attachment_import: {
            provider_key: "demo_cloud",
            attachments: [
              {
                file: uploaded_file,
                name: "Sample import",
                service_name: "mirror"
              }
            ]
          }
        )
      )

      RecordingStudioAttachable.configuration.stub(:upload_provider, provider) do
        payload = @controller.send(:attachment_payloads).first

        assert_equal "Sample import", payload[:name]
        assert_respond_to payload[:io], :read
        assert_equal "demo-import.svg", payload[:filename]
        assert_equal "image/svg+xml", payload[:content_type]
        assert_equal({ "provider" => "demo_cloud" }, payload[:metadata])
        assert_not_includes payload.keys, :service_name
        assert_not_includes payload.keys, :source
      end
    ensure
      tempfile.close!
    end

    def test_attachment_payloads_strip_provider_payload_to_allowed_keys
      @controller = AttachmentImportsController.new
      provider = Struct.new(:key, :allowed_payload_keys).new(:dropbox, %w[id])

      @controller.send(
        :params=,
        ActionController::Parameters.new(
          attachment_import: {
            provider_key: "dropbox",
            attachments: [
              {
                provider_payload: {
                  id: "file-1",
                  url: "https://dl.dropboxusercontent.com/s/stolen",
                  link: "https://evil.test"
                }
              }
            ]
          }
        )
      )

      RecordingStudioAttachable.configuration.stub(:upload_provider, provider) do
        payload = @controller.send(:attachment_payloads).first

        assert_equal({ "id" => "file-1" }, payload[:provider_payload])
      end
    end

    def test_create_authorizes_upload_before_adapter_imports
      @controller = AttachmentImportsController.new
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
      authorized = nil
      provider = Struct.new(:key, :allowed_payload_keys).new(:dropbox, %w[id])
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [])

      with_routing do |set|
        set.draw do
          post "/recordings/:recording_id/attachments/imports",
               to: "recording_studio_attachable/attachment_imports#create"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, lambda { |action, record, capability_options: {}|
            authorized = [action, record.id]
            true
          }) do
            @controller.stub(:capability_options_for, {}) do
              @controller.define_singleton_method(:recording_attachments_path) { |_recording| "/recordings/rec-1/attachments" }
              RecordingStudioAttachable.configuration.stub(:upload_provider, provider) do
                RecordingStudioAttachable::Services::ImportAttachmentPayloads.stub(:call, result) do
                  @controller.stub(:protect_against_forgery?, false) do
                    post :create,
                         params: {
                           recording_id: recording.id,
                           attachment_import: {
                             provider_key: "dropbox",
                             attachments: [{ provider_payload: { id: "file-1" } }]
                           }
                         },
                         as: :json
                  end
                end
              end
            end
          end
        end
      end

      assert_response :created
      assert_equal [:upload, "rec-1"], authorized
    end

    def test_create_imports_a_dropbox_chooser_selection_through_the_shared_endpoint
      @controller = AttachmentImportsController.new
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
      captured = nil
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [])
      original_providers = RecordingStudioAttachable.configuration.upload_providers.dup
      original_dropbox = RecordingStudioAttachable.configuration.dropbox.to_h

      RecordingStudioAttachable.configuration.dropbox.merge!(
        enabled: true,
        client_id: "dropbox-client-id"
      )
      RecordingStudioAttachable::Dropbox::Integration.stub(:gem_loaded?, true) do
        RecordingStudioAttachable::Dropbox::Engine.send(:register_upload_provider)
      end

      with_routing do |set|
        set.draw do
          post "/recordings/:recording_id/attachments/imports",
               to: "recording_studio_attachable/attachment_imports#create"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              @controller.define_singleton_method(:recording_attachments_path) { |_recording| "/recordings/#{recording.id}/attachments" }
              RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.stub(:call, lambda { |**kwargs|
                captured = kwargs
                result
              }) do
                @controller.stub(:protect_against_forgery?, false) do
                  post :create,
                       params: {
                         recording_id: recording.id,
                         attachment_import: {
                           provider_key: "dropbox",
                           attachments: [
                             {
                               name: "kiln.jpg",
                               description: "",
                               provider_key: "dropbox",
                               provider_payload: { id: "id:fia-lKYKs5AAAAAAAAAACw" },
                               content_type: ""
                             }
                           ]
                         }
                       },
                       as: :json
                end
              end
            end
          end
        end
      end

      assert_response :created
      assert_equal recording, captured[:parent_recording]
      assert_nil captured[:access_token]
      selection = captured[:file_ids].first
      assert_equal "id:fia-lKYKs5AAAAAAAAAACw", selection.fetch("id")
      assert_equal "kiln.jpg", selection.fetch("name")
    ensure
      RecordingStudioAttachable.configuration.dropbox.merge!(original_dropbox)
      RecordingStudioAttachable.configuration.instance_variable_set(:@upload_providers, original_providers)
    end

    def test_create_rejects_unknown_provider_keys
      @controller = AttachmentImportsController.new
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

      with_routing do |set|
        set.draw do
          post "/recordings/:recording_id/attachments/imports",
               to: "recording_studio_attachable/attachment_imports#create"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              RecordingStudioAttachable.configuration.stub(:upload_provider, nil) do
                @controller.stub(:protect_against_forgery?, false) do
                  post :create,
                       params: {
                         recording_id: recording.id,
                         attachment_import: {
                           provider_key: "missing_provider",
                           attachments: [{ signed_blob_id: "blob-1" }]
                         }
                       },
                       as: :json
                end
              end
            end
          end
        end
      end

      assert_response :unprocessable_entity
      assert_equal({ "error" => "Unknown upload provider", "errors" => [] }, JSON.parse(response.body))
    end

    def test_create_returns_explicit_redirect_path_for_json_imports
      @controller = AttachmentImportsController.new
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [])
      provider = Struct.new(:key).new(:google_drive)

      with_routing do |set|
        set.draw do
          post "/recordings/:recording_id/attachments/imports",
               to: "recording_studio_attachable/attachment_imports#create"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              RecordingStudioAttachable.configuration.stub(:upload_provider, provider) do
                RecordingStudioAttachable::Services::ImportAttachmentPayloads.stub(:call, result) do
                  @controller.stub(:protect_against_forgery?, false) do
                    post :create,
                         params: {
                           recording_id: recording.id,
                           redirect_mode: "return_to",
                           return_to: "/pages/page-1#gallery",
                           attachment_import: {
                             provider_key: "google_drive",
                             attachments: [{ signed_blob_id: "blob-1", name: "Drive file" }]
                           }
                         },
                         as: :json
                  end
                end
              end
            end
          end
        end
      end

      assert_response :created
      assert_equal "/pages/page-1#gallery", JSON.parse(@response.body).fetch("redirect_path")
    end

    private

    def uploaded_svg_file
      tempfile = Tempfile.new(["demo-import", ".svg"])
      tempfile.write("<svg></svg>")
      tempfile.rewind

      [
        ActionDispatch::Http::UploadedFile.new(
          tempfile: tempfile,
          filename: "demo-import.svg",
          type: "image/svg+xml"
        ),
        tempfile
      ]
    end

    def ensure_recording_lookup!
      studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
      studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

      return if RecordingStudio::Recording.respond_to?(:find)

      RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
    end
  end
end
