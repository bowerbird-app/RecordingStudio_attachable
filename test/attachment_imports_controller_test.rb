# frozen_string_literal: true

require "tempfile"

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/attachment_imports_controller"
require_relative "../lib/recording_studio_attachable/services/base_service"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/import_attachments"
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
                RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, lambda { |**kwargs|
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
      assert_equal "google_drive", captured[:default_source]
      assert_equal [{ signed_blob_id: "blob-1", name: "Drive file", metadata: { "external_id" => "file-1", "provider" => "google_drive" } }],
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
        refute_includes payload.keys, :service_name
        refute_includes payload.keys, :source
      end
    ensure
      tempfile.close!
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
                RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, result) do
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
