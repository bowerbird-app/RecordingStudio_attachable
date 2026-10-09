# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/libraries_controller"
require_relative "../lib/recording_studio_attachable/services/base_service"

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

      with_library_routes do
        RecordingStudio::Recording.stub(:find, root) do
          @controller.stub(:authorize_library_action!, true) do
            RecordingStudioAttachable.stub(:library_for, library) do
              get :show, params: { id: root.id }
            end
          end
        end
      end

      assert_redirected_to "/recordings/#{library.id}/attachments?kind=images"
    end

    def test_show_opens_an_existing_named_library
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

    def test_index_assigns_libraries_for_the_parent
      parent = FakeRecording.new(id: "root-1", recordable_type: "Workspace")
      library = FakeRecording.new(id: "lib-1", recordable_type: "RecordingStudioAttachable::Library")

      with_routing do |set|
        set.draw do
          get "recordings/:recording_id/libraries", to: "recording_studio_attachable/libraries#index"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_library_action!, true) do
            RecordingStudioAttachable.stub(:libraries_for, [library]) do
              RecordingStudioAttachable::Authorization.stub(:library_allowed?, true) do
                RecordingStudioAttachable::Placements.stub(:usage_for_library, []) do
                  @controller.define_singleton_method(:default_render) do
                    render plain: [@parent_recording.id, @libraries.size, @can_manage].join("|")
                  end

                  get :index, params: { recording_id: parent.id }
                end
              end
            end
          end
        end
      end

      assert_response :success
      assert_equal "root-1|1|true", @response.body
    end

    def test_create_makes_a_named_library
      parent = FakeRecording.new(id: "root-1", recordable_type: "Workspace")
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: parent)
      captured = nil

      with_routing do |set|
        set.draw do
          post "recordings/:recording_id/libraries", to: "recording_studio_attachable/libraries#create"
          get "recordings/:recording_id/libraries",
              to: "recording_studio_attachable/libraries#index",
              as: :recording_libraries
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_library_action!, true) do
            @controller.stub(:protect_against_forgery?, false) do
              RecordingStudioAttachable::Services::CreateLibrary.stub(
                :call,
                lambda { |**kwargs|
                  captured = kwargs
                  result
                }
              ) do
                post :create, params: { recording_id: parent.id, library: { name: "Campaign stills" } }
              end
            end
          end
        end
      end

      assert_redirected_to "/recordings/#{parent.id}/libraries"
      assert_equal "Campaign stills", captured[:name]
    end

    def test_update_renames_a_library
      parent = FakeRecording.new(id: "root-1", recordable_type: "Workspace")
      library = FakeRecording.new(id: "lib-1", recordable_type: "RecordingStudioAttachable::Library", parent_recording: parent)
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: library)
      captured = nil

      with_routing do |set|
        set.draw do
          patch "libraries/:id", to: "recording_studio_attachable/libraries#update"
          get "recordings/:recording_id/libraries",
              to: "recording_studio_attachable/libraries#index",
              as: :recording_libraries
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, library) do
          @controller.stub(:authorize_library_action!, true) do
            @controller.stub(:protect_against_forgery?, false) do
              RecordingStudioAttachable::Services::RenameLibrary.stub(
                :call,
                lambda { |**kwargs|
                  captured = kwargs
                  result
                }
              ) do
                patch :update, params: { id: library.id, library: { name: "Kiln shots" } }
              end
            end
          end
        end
      end

      assert_redirected_to "/recordings/#{parent.id}/libraries"
      assert_equal "Kiln shots", captured[:name]
    end

    def test_destroy_trashes_a_library
      parent = FakeRecording.new(id: "root-1", recordable_type: "Workspace")
      library = FakeRecording.new(id: "lib-1", recordable_type: "RecordingStudioAttachable::Library", parent_recording: parent)
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: library)
      captured = nil

      with_routing do |set|
        set.draw do
          delete "libraries/:id", to: "recording_studio_attachable/libraries#destroy"
          get "recordings/:recording_id/libraries",
              to: "recording_studio_attachable/libraries#index",
              as: :recording_libraries
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, library) do
          @controller.stub(:authorize_library_action!, true) do
            @controller.stub(:protect_against_forgery?, false) do
              RecordingStudioAttachable::Services::TrashLibrary.stub(
                :call,
                lambda { |**kwargs|
                  captured = kwargs
                  result
                }
              ) do
                delete :destroy, params: { id: library.id }
              end
            end
          end
        end
      end

      assert_redirected_to "/recordings/#{parent.id}/libraries"
      assert_equal library, captured[:library_recording]
    end

    private

    def with_library_routes(&)
      with_routing do |set|
        set.draw do
          get "libraries/:id", to: "recording_studio_attachable/libraries#show", as: :library
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
