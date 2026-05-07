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

    def test_download_redirects_to_attachment_blob_path
      file = Object.new
      attachment = Struct.new(:file).new(file)
      attachment_recording = FakeRecording.new(
        id: "att-1",
        recordable_type: "RecordingStudioAttachable::Attachment",
        recordable: attachment
      )
      main_app = Object.new
      main_app.define_singleton_method(:rails_blob_path) do |passed_file, disposition:|
        raise "wrong file" unless passed_file.equal?(file)
        raise "wrong disposition" unless disposition == :attachment

        "/rails/active_storage/blobs/download"
      end

      with_routing do |set|
        set.draw do
          get "/attachments/:id/download", to: "recording_studio_attachable/attachments#download"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, attachment_recording) do
          @controller.stub(:authorize_attachment_owner_action!, true) do
            @controller.define_singleton_method(:main_app) { main_app }
            get :download, params: { id: attachment_recording.id }
          end
        end
      end

      assert_redirected_to "/rails/active_storage/blobs/download"
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
