# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/recording_attachments_controller"
require_relative "../app/queries/recording_studio_attachable/queries/for_recording"

module RecordingStudioAttachable
  class RecordingAttachmentsControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable, :recordable_type, keyword_init: true)
    FakeQuery = Struct.new(:call_result, :current_page, :total_pages, :total_count, keyword_init: true) do
      def call
        call_result
      end
    end

    def setup
      ensure_recording_lookup!
    end

    def test_index_defaults_to_list_view_for_files
      assert_equal "list", render_view_mode_for(kind: "files")
    end

    def test_index_defaults_to_grid_view_for_non_file_kinds_and_accepts_explicit_override
      assert_equal "grid", render_view_mode_for(kind: "all")
      assert_equal "list", render_view_mode_for(kind: "all", view: "list")
    end

    private

    def render_view_mode_for(kind:, view: nil)
      @controller = RecordingAttachmentsController.new
      recording = FakeRecording.new(id: "parent-1", recordable: Object.new, recordable_type: "Workspace")
      query = FakeQuery.new(call_result: [], current_page: 1, total_pages: 1, total_count: 0)

      with_routing do |set|
        set.draw do
          get "/recordings/:recording_id/attachments",
              to: "recording_studio_attachable/recording_attachments#index"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, recording) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:capability_options_for, {}) do
              RecordingStudioAttachable::Queries::ForRecording.stub(:new, ->(**_kwargs) { query }) do
                RecordingStudioAttachable::Authorization.stub(:allowed?, false) do
                  @controller.define_singleton_method(:default_render) { render plain: @view_mode.to_s }

                  get :index, params: { recording_id: recording.id, kind: kind, view: view }
                end
              end
            end
          end
        end
      end

      @response.body
    end

    def ensure_recording_lookup!
      studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
      studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)

      return if RecordingStudio::Recording.respond_to?(:find)

      RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
    end
  end
end
