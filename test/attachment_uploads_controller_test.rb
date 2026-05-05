# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/attachment_uploads_controller"

module RecordingStudioAttachable
  class AttachmentUploadsControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)

    def setup
      ensure_recording_lookup!
    end

    def test_attachment_payloads_permits_nested_json_attachment_fields
      @controller = AttachmentUploadsController.new
      @controller.send(
        :params=,
        ActionController::Parameters.new(
          attachments: [
            {
              signed_blob_id: "blob-1",
              name: "bike rack plans",
              description: ""
            }
          ],
          attachment_upload: {
            attachments: [
              {
                signed_blob_id: "blob-1",
                name: "bike rack plans",
                description: "",
                ignored: "value"
              }
            ]
          }
        )
      )

      assert_equal(
        [{ signed_blob_id: "blob-1", name: "bike rack plans", description: "" }],
        @controller.send(:attachment_payloads)
      )
    end

    def test_create_passes_nil_impersonator_when_current_does_not_define_it
      @controller = AttachmentUploadsController.new
      recording = FakeRecording.new(id: "rec-1", recordable_type: "Workspace")
      original_current = Object.send(:remove_const, :Current) if defined?(Current)
      current = Object.const_set(:Current, Class.new)
      captured = nil

      current.define_singleton_method(:actor) { :actor }

      RecordingStudio::Recording.define_singleton_method(:find) { |_id| recording }

      with_routing do |set|
        set.draw do
          post "/recordings/:recording_id/attachments",
               to: "recording_studio_attachable/attachment_uploads#create"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              @controller.define_singleton_method(:recording_attachments_path) { |_recording| "/recordings/#{recording.id}/attachments" }
              @controller.stub(:recording_attachments_path, "/recordings/#{recording.id}/attachments") do
              result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [])

                RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, lambda { |**kwargs|
                  captured = kwargs
                  result
                }) do
                  @controller.stub(:protect_against_forgery?, false) do
                    post :create,
                         params: { recording_id: recording.id, attachments: [{ signed_blob_id: "blob-1", name: "one", description: "" }] },
                         as: :json
                  end
                end
              end
            end
          end
        end
      end

      assert_response :created
      assert_equal :actor, captured[:actor]
      assert_nil captured[:impersonator]
      assert_equal recording, captured[:parent_recording]
      assert_equal [{ signed_blob_id: "blob-1", name: "one", description: "" }], captured[:attachments]
    ensure
      current.singleton_class.send(:remove_method, :actor) if current.respond_to?(:actor)
      Object.send(:remove_const, :Current) if defined?(Current)
      Object.const_set(:Current, original_current) if original_current
    end

    private

    def ensure_current_class
      return Current if defined?(Current)

      Object.const_set(:Current, Class.new)
    end

    def ensure_recording_lookup!
      studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
      return if defined?(RecordingStudio::Recording)

      studio.const_set(:Recording, Class.new)
    end
  end
end
