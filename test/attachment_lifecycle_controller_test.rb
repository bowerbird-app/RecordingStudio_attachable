# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/attachment_lifecycle_controller"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/remove_attachment"
require_relative "../lib/recording_studio_attachable/services/base_service"

module RecordingStudioAttachable
  class AttachmentLifecycleControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

    def setup
      @controller = AttachmentLifecycleController.new
      ensure_recording_lookup!
      @controller.define_singleton_method(:recording_attachments_path) do |recording|
        "/recordings/#{recording.id}/attachments"
      end
    end

    def test_destroy_with_return_to_redirects_there
      delete_attachment(redirect_mode: "return_to", return_to: "/attachment_editor")

      assert_redirected_to "/attachment_editor"
    end

    def test_destroy_without_return_to_stays_on_the_library
      delete_attachment({})

      assert_redirected_to "/recordings/parent-1/attachments"
    end

    def test_destroy_ignores_an_off_site_return_to
      delete_attachment(redirect_mode: "return_to", return_to: "https://evil.example/phish")

      assert_redirected_to "/recordings/parent-1/attachments"
    end

    private

    def ensure_recording_lookup!
      studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
      studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)
      return if RecordingStudio::Recording.respond_to?(:find)

      RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
    end

    def delete_attachment(extra)
      attachment = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment")
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      result = Services::BaseService::Result.new(success: true, value: attachment)

      with_routing do |set|
        set.draw do
          delete "/attachments/:id", to: "recording_studio_attachable/attachment_lifecycle#destroy"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, attachment) do
          @controller.stub(:authorize_attachment_owner_action!, true) do
            @controller.stub(:attachable_owner_recording, parent) do
              Services::RemoveAttachment.stub(:call, ->(**) { result }) do
                @controller.stub(:protect_against_forgery?, false) do
                  delete :destroy, params: { id: attachment.id }.merge(extra)
                end
              end
            end
          end
        end
      end
    end
  end
end
