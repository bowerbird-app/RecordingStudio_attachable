# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/attachment_uploads_controller"
require_relative "../app/services/recording_studio_attachable/services/record_attachment_uploads"
require_relative "../lib/recording_studio_attachable/services/base_service"

module RecordingStudioAttachable
  class AttachmentUploadsControllerAdditionalTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable_type, :recordable, keyword_init: true)
    FakeAttachment = Struct.new(:name, :description, :content_type, :byte_size, :attachment_kind, :file, keyword_init: true)

    def setup
      @controller = AttachmentUploadsController.new
      ensure_recording_lookup!
    end

    def test_create_returns_json_error_payload_with_nested_errors
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
      result = RecordingStudioAttachable::Services::BaseService::Result.new(
        success: false,
        error: "upload failed",
        errors: [{ name: "one", error: "bad file" }]
      )

      with_routing do |set|
        set.draw do
          post "/recordings/:recording_id/attachments",
               to: "recording_studio_attachable/attachment_uploads#create"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, result) do
                @controller.stub(:protect_against_forgery?, false) do
                  post :create,
                       params: { recording_id: recording.id, attachments: [{ signed_blob_id: "blob-1", name: "one" }] },
                       as: :json
                end
              end
            end
          end
        end
      end

      assert_response :unprocessable_entity
      payload = JSON.parse(@response.body)
      assert_equal "upload failed", payload.fetch("error")
      assert_equal [{ "name" => "one", "error" => "bad file" }], payload.fetch("errors")
    end

    def test_create_returns_attachment_json_payload_for_uploaded_attachments
      attachment = FakeAttachment.new(
        name: "Hero image",
        description: "Lead image",
        content_type: "image/png",
        byte_size: 1024,
        attachment_kind: "image",
        file: Object.new
      )
      created_recording = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment", recordable: attachment)
      parent_recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [created_recording])

      with_routing do |set|
        set.draw do
          post "/recordings/:recording_id/attachments",
               to: "recording_studio_attachable/attachment_uploads#create"
          get "/attachments/:id", to: "recording_studio_attachable/attachments#show"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, parent_recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              @controller.define_singleton_method(:attachment_path) { |recording| "/attachments/#{recording.id}" }
              @controller.define_singleton_method(:authorized_attachment_preview_path) do |recording, variant_name|
                "/attachments/#{recording.id}/preview/#{variant_name}"
              end
              @controller.define_singleton_method(:authorized_attachment_file_path) { |recording| "/attachments/#{recording.id}/file" }
              @controller.define_singleton_method(:recording_attachments_path) { |recording| "/recordings/#{recording.id}/attachments" }
              RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, result) do
                @controller.stub(:protect_against_forgery?, false) do
                  post :create,
                       params: { recording_id: parent_recording.id, attachments: [{ signed_blob_id: "blob-1", name: "one" }] },
                       as: :json
                end
              end
            end
          end
        end
      end

      assert_response :created
      payload = JSON.parse(@response.body)
      attachment_payload = payload.fetch("attachments").first
      assert_equal "att-1", attachment_payload.fetch("id")
      assert_equal "Hero image", attachment_payload.fetch("name")
      assert_equal "/attachments/att-1/preview/square_small", attachment_payload.fetch("thumbnail_url")
      assert_equal "/attachments/att-1/file", attachment_payload.fetch("insert_url")
      assert_equal(
        {
          "small" => "/attachments/att-1/preview/small",
          "medium" => "/attachments/att-1/preview/med",
          "large" => "/attachments/att-1/preview/large"
        },
        attachment_payload.fetch("variant_urls")
      )
      assert_equal "/attachments/att-1", attachment_payload.fetch("show_path")
    end

    def test_create_html_failure_redirects_back_to_upload_page_with_redirect_params
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: "upload failed")

      with_routing do |set|
        set.draw do
          post "/recordings/:recording_id/attachments",
               to: "recording_studio_attachable/attachment_uploads#create"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              @controller.define_singleton_method(:recording_attachment_upload_path) do |_recording, options = {}|
                suffix = options.compact.to_query
                path = "/recordings/#{recording.id}/attachments/upload"
                suffix.present? ? "#{path}?#{suffix}" : path
              end
              RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, result) do
                @controller.stub(:protect_against_forgery?, false) do
                  post :create,
                       params: {
                         recording_id: recording.id,
                         redirect_mode: "return_to",
                         return_to: "/pages/page-1#hero-image",
                         attachments: [{ signed_blob_id: "blob-1", name: "one" }]
                       }
                end
              end
            end
          end
        end
      end

      assert_redirected_to "/recordings/rec-1/attachments/upload?redirect_mode=return_to&return_to=%2Fpages%2Fpage-1%23hero-image"
      assert_equal "upload failed", flash[:alert]
    end

    def test_new_uses_attachment_imports_path_for_shared_queue_finalization
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")

      with_routing do |set|
        set.draw do
          get "/recordings/:recording_id/attachments/upload",
              to: "recording_studio_attachable/attachment_uploads#new"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              configured_option = lambda { |_recording, option_name|
                {
                  allowed_content_types: ["image/*"],
                  max_file_size: 25.megabytes,
                  max_file_count: 20,
                  image_processing_enabled: true,
                  image_processing_max_width: 2048,
                  image_processing_max_height: 2048,
                  image_processing_quality: 0.8
                }.fetch(option_name)
              }

              @controller.stub(:configured_attachable_option, configured_option) do
                @controller.stub(:configured_upload_providers, []) do
                  @controller.define_singleton_method(:recording_attachment_imports_path) do |_recording, options = {}|
                    suffix = options.to_h.to_query
                    path = "/recordings/#{recording.id}/attachments/imports"
                    suffix.present? ? "#{path}?#{suffix}" : path
                  end
                  @controller.define_singleton_method(:default_render) do
                    render plain: @create_path
                  end

                  get :new, params: { recording_id: recording.id, redirect_mode: "return_to", return_to: "/pages/page-1#gallery" }
                end
              end
            end
          end
        end
      end

      assert_response :success
      assert_equal "/recordings/rec-1/attachments/imports?redirect_mode=return_to&return_to=%2Fpages%2Fpage-1%23gallery", @response.body
    end

    private

    def ensure_recording_lookup!
      studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
      studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

      return if RecordingStudio::Recording.respond_to?(:find)

      RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
    end
  end
end
