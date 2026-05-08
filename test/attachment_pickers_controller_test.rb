# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/attachment_pickers_controller"
require_relative "../app/queries/recording_studio_attachable/queries/for_recording"

module RecordingStudioAttachable
  class AttachmentPickersControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable, :recordable_type, keyword_init: true)
    FakeAttachment = Struct.new(:name, :description, :content_type, :byte_size, :attachment_kind, :file, keyword_init: true)
    FakeQuery = Struct.new(:call_result, :current_page, :total_pages, :total_count, keyword_init: true) do
      def call
        call_result
      end

      def next_page?
        current_page < total_pages
      end

      def previous_page?
        current_page > 1
      end
    end

    def test_index_returns_image_picker_payload_and_forces_image_kind
      @controller = AttachmentPickersController.new
      recording = FakeRecording.new(id: "parent-1", recordable_type: "Page")
      attachment = FakeAttachment.new(
        name: "Hero image",
        description: "Lead image",
        content_type: "image/png",
        byte_size: 1024,
        attachment_kind: "image",
        file: Object.new
      )
      attachment_recording = FakeRecording.new(id: "attachment-1", recordable: attachment)
      query = FakeQuery.new(call_result: [attachment_recording], current_page: 2, total_pages: 4, total_count: 7)
      query_options = nil

      with_routing do |set|
        set.draw do
          get "/recordings/:recording_id/attachments/picker",
              to: "recording_studio_attachable/attachment_pickers#index"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              @controller.define_singleton_method(:attachment_path) { |attachment_rec| "/attachments/#{attachment_rec.id}" }
              @controller.define_singleton_method(:authorized_attachment_preview_path) do |attachment_rec, variant_name|
                "/attachments/#{attachment_rec.id}/preview/#{variant_name}"
              end
              @controller.define_singleton_method(:authorized_attachment_file_path) { |attachment_rec| "/attachments/#{attachment_rec.id}/file" }

              RecordingStudioAttachable::Queries::ForRecording.stub(:new, lambda { |**kwargs|
                query_options = kwargs
                query
              }) do
                get :index, params: { recording_id: recording.id, q: "hero", page: 2, kind: "files" }, as: :json
              end
            end
          end
        end
      end

      assert_response :success
      assert_equal :images, query_options[:kind]
      assert_equal "hero", query_options[:search]
      assert_equal "2", query_options[:page]

      payload = JSON.parse(@response.body)
      assert_equal 2, payload.dig("pagination", "current_page")
      assert_equal 4, payload.dig("pagination", "total_pages")
      assert_equal 7, payload.dig("pagination", "total_count")
      assert_equal true, payload.dig("pagination", "next_page")
      assert_equal true, payload.dig("pagination", "previous_page")

      attachment_payload = payload.fetch("attachments").first
      assert_equal "attachment-1", attachment_payload.fetch("id")
      assert_equal "Hero image", attachment_payload.fetch("name")
      assert_equal "Lead image", attachment_payload.fetch("description")
      assert_equal "image/png", attachment_payload.fetch("content_type")
      assert_equal 1024, attachment_payload.fetch("byte_size")
      assert_equal "image", attachment_payload.fetch("attachment_kind")
      assert_equal "/attachments/attachment-1/preview/square_small", attachment_payload.fetch("thumbnail_url")
      assert_equal "/attachments/attachment-1/file", attachment_payload.fetch("insert_url")
      assert_equal "Hero image", attachment_payload.fetch("alt")
      assert_equal "/attachments/attachment-1", attachment_payload.fetch("show_path")
    end

    private

    def ensure_recording_lookup!
      studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
      studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

      return if RecordingStudio::Recording.respond_to?(:find)

      RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
    end

    def setup
      ensure_recording_lookup!
    end
  end
end
