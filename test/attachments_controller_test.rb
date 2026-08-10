# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/attachments_controller"
require_relative "../app/services/recording_studio_attachable/services/replace_attachment_file"
require_relative "../app/services/recording_studio_attachable/services/revise_attachment_metadata"
require_relative "../lib/recording_studio_attachable/services/base_service"

module RecordingStudioAttachable
  class AttachmentsControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable_type, :recordable, keyword_init: true)

    def setup
      @controller = AttachmentsController.new
      ensure_recording_lookup!
    end

    def test_show_assigns_owner_and_attachment_configuration
      attachment = Struct.new(:name, :description, :original_filename, :file).new("Hero", "", "hero.png", Object.new)
      attachment_recording = FakeRecording.new(
        id: "att-1",
        recordable_type: "RecordingStudioAttachable::Attachment",
        recordable: attachment
      )
      owner = FakeRecording.new(id: "owner-1", recordable_type: "Workspace")

      with_routing do |set|
        set.draw do
          get "/attachments/:id", to: "recording_studio_attachable/attachments#show"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, attachment_recording) do
          @controller.stub(:authorize_attachment_owner_action!, true) do
            configured_option = lambda { |_recording, option_name|
              {
                allowed_content_types: ["image/*"],
                max_file_size: 25.megabytes,
                image_processing_enabled: true,
                image_processing_max_width: 1600,
                image_processing_max_height: 1200,
                image_processing_quality: 0.72
              }.fetch(option_name)
            }

            @controller.stub(:configured_attachable_option, configured_option) do
              @controller.stub(:attachable_owner_recording, owner) do
                @controller.define_singleton_method(:default_render) do
                  render plain: [@attachment.name, @owner_recording.id, @replace_allowed_content_types.join(",")].join("|")
                end

                get :show, params: { id: attachment_recording.id }
              end
            end
          end
        end
      end

      assert_response :success
      assert_equal "Hero|owner-1|image/*", @response.body
    end

    def test_update_replaces_attachment_file_when_signed_blob_id_is_present
      attachment_recording = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment")
      updated_recording = FakeRecording.new(id: "att-2", recordable_type: "RecordingStudioAttachable::Attachment")
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: updated_recording)
      captured = nil

      with_routing do |set|
        set.draw do
          patch "/attachments/:id", to: "recording_studio_attachable/attachments#update"
          get "/attachments/:id", to: "recording_studio_attachable/attachments#show"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, attachment_recording) do
          @controller.stub(:authorize_attachment_owner_action!, true) do
            @controller.define_singleton_method(:attachment_path) { |recording| "/attachments/#{recording.id}" }
            @controller.stub(:current_attachable_actor, :actor) do
              @controller.stub(:current_attachable_impersonator, :impersonator) do
                RecordingStudioAttachable::Services::ReplaceAttachmentFile.stub(:call, lambda { |**kwargs|
                  captured = kwargs
                  result
                }) do
                  @controller.stub(:protect_against_forgery?, false) do
                    patch :update, params: {
                      id: attachment_recording.id,
                      attachment: {
                        signed_blob_id: "blob-1",
                        name: "Updated",
                        description: "New description"
                      }
                    }
                  end
                end
              end
            end
          end
        end
      end

      assert_redirected_to "/attachments/att-2"
      assert_equal "Saved", flash[:notice]
      assert_equal attachment_recording, captured[:attachment_recording]
      assert_equal :actor, captured[:actor]
      assert_equal :impersonator, captured[:impersonator]
      assert_equal "blob-1", captured[:signed_blob_id]
    end

    def test_update_revises_metadata_when_signed_blob_id_is_blank
      attachment_recording = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment")
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: "revision failed")
      captured = nil

      with_routing do |set|
        set.draw do
          patch "/attachments/:id", to: "recording_studio_attachable/attachments#update"
          get "/attachments/:id", to: "recording_studio_attachable/attachments#show"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, attachment_recording) do
          @controller.stub(:authorize_attachment_owner_action!, true) do
            @controller.define_singleton_method(:attachment_path) { |recording| "/attachments/#{recording.id}" }
            @controller.stub(:current_attachable_actor, :actor) do
              @controller.stub(:current_attachable_impersonator, :impersonator) do
                RecordingStudioAttachable::Services::ReviseAttachmentMetadata.stub(:call, lambda { |**kwargs|
                  captured = kwargs
                  result
                }) do
                  @controller.stub(:protect_against_forgery?, false) do
                    patch :update, params: {
                      id: attachment_recording.id,
                      attachment: {
                        signed_blob_id: "",
                        name: "Updated",
                        description: "New description"
                      }
                    }
                  end
                end
              end
            end
          end
        end
      end

      assert_redirected_to "/attachments/att-1"
      assert_equal "revision failed", flash[:alert]
      assert_equal attachment_recording, captured[:attachment_recording]
      assert_equal "Updated", captured[:name]
      assert_equal "New description", captured[:description]
    end

    FakeVariant = Struct.new(:processed_data, keyword_init: true) do
      def processed
        self
      end

      def download
        processed_data
      end
    end

    FakeFile = Struct.new(:downloaded_data, keyword_init: true) do
      def download
        downloaded_data
      end
    end

    def test_download_streams_attachment_data
      file = FakeFile.new(downloaded_data: "blob-bytes")
      attachment = Struct.new(:file, :original_filename, :content_type).new(file, "hero.png", "image/png")
      attachment_recording = FakeRecording.new(
        id: "att-1",
        recordable_type: "RecordingStudioAttachable::Attachment",
        recordable: attachment
      )

      with_routing do |set|
        set.draw do
          get "/attachments/:id/download", to: "recording_studio_attachable/attachments#download"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, attachment_recording) do
          @controller.stub(:authorize_attachment_owner_action!, true) do
            get :download, params: { id: attachment_recording.id }
          end
        end
      end

      assert_response :success
      assert_equal "blob-bytes", @response.body
      assert_equal "attachment; filename=\"hero.png\"; filename*=UTF-8''hero.png", @response.headers["Content-Disposition"]
      assert_equal "image/png", @response.media_type
    end

    def test_file_streams_attachment_data_inline
      file = FakeFile.new(downloaded_data: "blob-bytes")
      attachment = Struct.new(:file, :original_filename, :content_type).new(file, "hero.png", "image/png")
      attachment_recording = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment", recordable: attachment)

      with_routing do |set|
        set.draw do
          get "/attachments/:id/file", to: "recording_studio_attachable/attachments#file"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, attachment_recording) do
          @controller.stub(:authorize_attachment_owner_action!, true) do
            get :file, params: { id: attachment_recording.id }
          end
        end
      end

      assert_response :success
      assert_equal "blob-bytes", @response.body
      assert_equal "inline; filename=\"hero.png\"; filename*=UTF-8''hero.png", @response.headers["Content-Disposition"]
    end

    def test_preview_streams_processed_variant_inline
      FakeVariant.new(processed_data: "preview-bytes")
      file = Struct.new(:variable?).new(true)
      attachment = Struct.new(:file, :original_filename, :content_type) do
        def preview_target_named(_variant_name)
          FakeVariant.new(processed_data: "preview-bytes")
        end
      end.new(file, "hero.png", "image/png")
      attachment_recording = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment", recordable: attachment)

      with_routing do |set|
        set.draw do
          get "/attachments/:id/preview/:variant_name", to: "recording_studio_attachable/attachments#preview"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, attachment_recording) do
          @controller.stub(:authorize_attachment_owner_action!, true) do
            get :preview, params: { id: attachment_recording.id, variant_name: "large" }
          end
        end
      end

      assert_response :success
      assert_equal "preview-bytes", @response.body
      assert_equal "inline; filename=\"hero.png\"; filename*=UTF-8''hero.png", @response.headers["Content-Disposition"]
    end

    def test_preview_returns_service_unavailable_when_processor_is_unavailable
      variant = Object.new
      variant.define_singleton_method(:processed) { nil.new }
      file = Struct.new(:variable?).new(true)
      attachment = Struct.new(:file, :original_filename, :content_type) do
        define_method(:preview_target_named) { |_variant_name| variant }
      end.new(file, "hero.png", "image/png")
      attachment_recording = FakeRecording.new(
        id: "att-1",
        recordable_type: "RecordingStudioAttachable::Attachment",
        recordable: attachment
      )
      log_messages = []
      test_logger = Object.new
      test_logger.define_singleton_method(:error) { |message| log_messages << message }

      with_preview_request(attachment_recording) do
        @controller.stub(:logger, test_logger) do
          ActiveStorage.stub(:variant_transformer, nil) do
            get :preview, params: { id: attachment_recording.id, variant_name: "large" }
          end
        end
      end

      assert_response :service_unavailable
      assert_equal "Image preview is temporarily unavailable", @response.body
      assert_includes log_messages.first, "attachment_recording_id=att-1"
      assert_includes log_messages.first, "variant=large"
      assert_includes log_messages.first, "NoMethodError"
    end

    def test_preview_does_not_rescue_unrelated_processing_errors
      variant = Object.new
      variant.define_singleton_method(:processed) { raise "storage unavailable" }
      file = Struct.new(:variable?).new(true)
      attachment = Struct.new(:file, :original_filename, :content_type) do
        define_method(:preview_target_named) { |_variant_name| variant }
      end.new(file, "hero.png", "image/png")
      attachment_recording = FakeRecording.new(
        id: "att-1",
        recordable_type: "RecordingStudioAttachable::Attachment",
        recordable: attachment
      )

      error = assert_raises(RuntimeError) do
        with_preview_request(attachment_recording) do
          get :preview, params: { id: attachment_recording.id, variant_name: "large" }
        end
      end

      assert_equal "storage unavailable", error.message
    end

    def test_preview_does_not_rescue_unrelated_load_errors
      variant = Object.new
      variant.define_singleton_method(:processed) { raise LoadError, "cannot load such file -- storage_adapter" }
      file = Struct.new(:variable?).new(true)
      attachment = Struct.new(:file, :original_filename, :content_type) do
        define_method(:preview_target_named) { |_variant_name| variant }
      end.new(file, "hero.png", "image/png")
      attachment_recording = FakeRecording.new(
        id: "att-1",
        recordable_type: "RecordingStudioAttachable::Attachment",
        recordable: attachment
      )

      assert_raises(LoadError) do
        with_preview_request(attachment_recording) do
          get :preview, params: { id: attachment_recording.id, variant_name: "large" }
        end
      end
    end

    def test_non_variable_unsafe_image_is_forced_to_download
      file = FakeFile.new(downloaded_data: "<svg></svg>")
      file.define_singleton_method(:variable?) { false }
      attachment = Struct.new(:file, :original_filename, :content_type) do
        define_method(:preview_target_named) { |_variant_name| self }
      end.new(file, "image.svg", "image/svg+xml")
      attachment_recording = FakeRecording.new(
        id: "att-1",
        recordable_type: "RecordingStudioAttachable::Attachment",
        recordable: attachment
      )

      with_preview_request(attachment_recording) do
        get :preview, params: { id: attachment_recording.id, variant_name: "large" }
      end

      assert_response :success
      assert_equal "attachment; filename=\"image.svg\"; filename*=UTF-8''image.svg", @response.headers["Content-Disposition"]
    end

    private

    def with_preview_request(attachment_recording, &block)
      with_routing do |set|
        set.draw do
          get "/attachments/:id/preview/:variant_name", to: "recording_studio_attachable/attachments#preview"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, attachment_recording) do
          @controller.stub(:authorize_attachment_owner_action!, true, &block)
        end
      end
    end

    def ensure_recording_lookup!
      studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
      studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

      return if RecordingStudio::Recording.respond_to?(:find)

      RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
    end
  end
end
