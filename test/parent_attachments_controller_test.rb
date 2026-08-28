# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/parent_attachments_controller"

module RecordingStudioAttachable
  class ParentAttachmentsControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable_type, :recordable, keyword_init: true)

    def setup
      @controller = ParentAttachmentsController.new
      ensure_recording_lookup!
    end

    def test_show_assigns_parent_attachment_slot
      parent = FakeRecording.new(id: "parent-1", recordable_type: "User")
      attachment = Struct.new(:name, :original_filename, :file).new("Profile", "profile.png", Object.new)
      attachment_recording = FakeRecording.new(
        id: "att-1",
        recordable_type: "RecordingStudioAttachable::Attachment",
        recordable: attachment
      )
      relation = Minitest::Mock.new
      relation.expect(:first, attachment_recording)
      parent.define_singleton_method(:attachments) { |**| relation }

      with_routing do |set|
        set.draw do
          get "/recordings/:recording_id/parent_attachment", to: "recording_studio_attachable/parent_attachments#show"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_attachment_action!, true) do
            RecordingStudio.stub(:capability_options, {
                                   allowed_content_types: ["image/*"],
                                   enabled_attachment_kinds: [:image],
                                   max_file_size: 25.megabytes,
                                   image_processing_enabled: true,
                                   image_processing_max_width: 1200,
                                   image_processing_max_height: 1200,
                                   image_processing_quality: 0.75
                                 }) do
              @controller.define_singleton_method(:default_render) do
                render plain: [
                  @attachment_recording&.id,
                  @return_to,
                  @replace_button_text,
                  @add_button_text
                ].join("|")
              end

              get :show, params: { recording_id: parent.id, return_to: "/users/parent-1" }
            end
          end
        end
      end

      assert_response :success
      assert_equal "att-1|/users/parent-1|Replace photo|Add photo", @response.body
      relation.verify
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
