# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/libraries_controller"

module RecordingStudioAttachable
  class LibrariesControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable_type, :parent_recording, keyword_init: true) do
      def to_param
        id
      end
    end

    def setup
      @controller = LibrariesController.new
      ensure_recording_lookup!
    end

    def test_show_creates_the_default_library_and_redirects_to_the_existing_index
      root = FakeRecording.new(id: "root-1", recordable_type: "Workspace")
      library = FakeRecording.new(id: "lib-1", recordable_type: "RecordingStudioAttachable::Library")
      captured = nil

      with_library_routes do
        RecordingStudio::Recording.stub(:find, root) do
          @controller.stub(:authorize_library_action!, true) do
            RecordingStudioAttachable.stub(:library_for, lambda { |parent, **kwargs|
              captured = [parent, kwargs]
              library
            }) do
              get :show, params: { recording_id: root.id }
            end
          end
        end
      end

      assert_redirected_to "/recordings/#{library.id}/attachments?kind=images"
      assert_equal root, captured.first
      assert_equal :default, captured.last[:key]
    end

    def test_show_opens_a_keyed_library_for_a_parent
      root = FakeRecording.new(id: "root-1", recordable_type: "Workspace")
      library = FakeRecording.new(id: "lib-campaign", recordable_type: "RecordingStudioAttachable::Library")
      captured = nil

      with_library_routes do
        RecordingStudio::Recording.stub(:find, root) do
          @controller.stub(:authorize_library_action!, true) do
            RecordingStudioAttachable.stub(:library_for, lambda { |parent, **kwargs|
              captured = [parent, kwargs]
              library
            }) do
              get :show, params: { recording_id: root.id, key: "campaign" }
            end
          end
        end
      end

      assert_redirected_to "/recordings/#{library.id}/attachments?kind=images"
      assert_equal "campaign", captured.last[:key]
    end

    def test_show_opens_an_existing_library
      library = FakeRecording.new(id: "lib-2", recordable_type: "RecordingStudioAttachable::Library")

      with_library_routes do
        RecordingStudio::Recording.stub(:find, library) do
          @controller.stub(:authorize_library_action!, true) do
            get :show, params: { id: library.id }
          end
        end
      end

      assert_redirected_to "/recordings/#{library.id}/attachments?kind=images"
    end

    def test_controller_does_not_expose_index_create_update_or_destroy
      refute_includes LibrariesController.public_instance_methods(false), :index
      refute_includes LibrariesController.public_instance_methods(false), :create
      refute_includes LibrariesController.public_instance_methods(false), :update
      refute_includes LibrariesController.public_instance_methods(false), :destroy
    end

    private

    def with_library_routes(&)
      with_routing do |set|
        set.draw do
          get "libraries/:id", to: "recording_studio_attachable/libraries#show", as: :library
          get "recordings/:recording_id/library",
              to: "recording_studio_attachable/libraries#show",
              as: :recording_library
          get "recordings/:recording_id/attachments",
              to: "recording_studio_attachable/recording_attachments#index",
              as: :recording_attachments
        end

        @routes = set
        yield
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
