# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/attachment_collections_controller"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/revise_attachment_collection"
require_relative "../lib/recording_studio_attachable/services/base_service"

module RecordingStudioAttachable
  class AttachmentCollectionsControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

    def setup
      @controller = AttachmentCollectionsController.new
      ensure_recording_lookup!
    end

    def test_update_redirects_see_other_to_return_to_with_saved_notice
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      result = Services::BaseService::Result.new(success: true, value: parent)
      captured = nil

      with_routing do |set|
        set.draw do
          patch "/recordings/:recording_id/attachment_collection",
                to: "recording_studio_attachable/attachment_collections#update"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_attachment_action!, true) do
            Services::ReviseAttachmentCollection.stub(:call, lambda { |**kwargs|
              captured = kwargs
              result
            }) do
              @controller.stub(:protect_against_forgery?, false) do
                patch :update, params: {
                  recording_id: parent.id,
                  redirect_mode: "return_to",
                  return_to: "/attachment_editor",
                  attachment_collection: {
                    signed_editor: "token",
                    fields: ["caption"],
                    rows: [{ recording_id: "image-1", caption: "Pier light", alt_text: "Sneaky" }]
                  }
                }
              end
            end
          end
        end
      end

      assert_redirected_to "/attachment_editor"
      assert_equal 303, @response.status
      assert_equal "Saved.", flash[:notice]
      assert_equal parent, captured[:recording]
      assert_equal "token", captured[:params].dig(:attachment_collection, :signed_editor)
      assert_nil captured[:params].dig(:attachment_collection, :fields)
      assert_equal "Pier light", captured[:params].dig(:attachment_collection, :rows, 0, :caption)
    end

    def test_update_without_return_to_goes_to_the_attachment_index
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      result = Services::BaseService::Result.new(success: true, value: parent)

      with_routing do |set|
        set.draw do
          patch "/recordings/:recording_id/attachment_collection",
                to: "recording_studio_attachable/attachment_collections#update"
        end

        @routes = set

        @controller.define_singleton_method(:recording_attachments_path) do |recording|
          "/recordings/#{recording.id}/attachments"
        end

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_attachment_action!, true) do
            Services::ReviseAttachmentCollection.stub(:call, ->(**) { result }) do
              @controller.stub(:protect_against_forgery?, false) do
                patch :update, params: {
                  recording_id: parent.id,
                  attachment_collection: { signed_editor: "token", rows: [] }
                }
              end
            end
          end
        end
      end

      assert_redirected_to "/recordings/parent-1/attachments"
      assert_equal 303, @response.status
      assert_equal "Saved.", flash[:notice]
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
