# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/libraries_controller"

module RecordingStudioAttachable
  class LibrariesControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true) do
      def to_param
        id
      end
    end

    def setup
      @controller = LibrariesController.new
      ensure_recording_lookup!
    end

    def test_show_creates_the_library_and_redirects_to_the_existing_index
      root = FakeRecording.new(id: "root-1", recordable_type: "Workspace")
      library = FakeRecording.new(id: "lib-1", recordable_type: "RecordingStudioAttachable::Library")

      with_routing do |set|
        set.draw do
          get "libraries/:root_recording_id", to: "recording_studio_attachable/libraries#show", as: :library
          get "recordings/:recording_id/attachments",
              to: "recording_studio_attachable/recording_attachments#index",
              as: :recording_attachments
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, root) do
          @controller.stub(:authorize_root_view!, true) do
            RecordingStudioAttachable.stub(:library_for, library) do
              get :show, params: { root_recording_id: root.id }
            end
          end
        end
      end

      assert_redirected_to "/recordings/#{library.id}/attachments?kind=images"
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
