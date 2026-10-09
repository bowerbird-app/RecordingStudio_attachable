# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/placements_controller"
require_relative "../lib/recording_studio_attachable/services/base_service"

module RecordingStudioAttachable
  class PlacementsControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable_type, :parent_recording, :root_recording, keyword_init: true) do
      def to_param
        id
      end
    end

    def setup
      @controller = PlacementsController.new
      ensure_recording_lookup!
    end

    def test_index_assigns_resolved_placements_and_the_library
      parent = FakeRecording.new(id: "gallery-1", recordable_type: "Gallery")
      library = FakeRecording.new(id: "lib-1", recordable_type: "RecordingStudioAttachable::Library")
      resolved = [RecordingStudioAttachable::Placements::Resolved.new(placement_recording: parent)]

      with_routing do |set|
        set.draw do
          get "recordings/:recording_id/placements", to: "recording_studio_attachable/placements#index"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_placement_action!, true) do
            RecordingStudioAttachable::Placements.stub(:resolve, resolved) do
              RecordingStudioAttachable.stub(:library_for, library) do
                RecordingStudioAttachable::Authorization.stub(:placement_allowed?, true) do
                  @controller.define_singleton_method(:default_render) do
                    render plain: [@recording.id, @library.id, @resolved.size, @can_add].join("|")
                  end

                  get :index, params: { recording_id: parent.id }
                end
              end
            end
          end
        end
      end

      assert_response :success
      assert_equal "gallery-1|lib-1|1|true", @response.body
    end

    def test_create_places_an_existing_library_image
      parent = FakeRecording.new(id: "gallery-1", recordable_type: "Gallery")
      attachment = FakeRecording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment")
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: parent)
      captured = nil

      with_routing do |set|
        set.draw do
          post "recordings/:recording_id/placements", to: "recording_studio_attachable/placements#create"
          get "recordings/:recording_id/placements",
              to: "recording_studio_attachable/placements#index",
              as: :recording_placements
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, ->(id) { id.to_s == "att-1" ? attachment : parent }) do
          @controller.stub(:authorize_placement_action!, true) do
            @controller.stub(:protect_against_forgery?, false) do
              RecordingStudioAttachable::Services::PlaceLibraryImage.stub(
                :call,
                lambda { |**kwargs|
                  captured = kwargs
                  result
                }
              ) do
                post :create, params: { recording_id: parent.id, placement: { attachment_recording_id: attachment.id } }
              end
            end
          end
        end
      end

      assert_redirected_to "/recordings/#{parent.id}/placements"
      assert_equal parent, captured[:parent_recording]
      assert_equal attachment, captured[:attachment_recording]
    end

    def test_reorder_uses_orderable_and_redirects
      parent = FakeRecording.new(id: "gallery-1", recordable_type: "Gallery")
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: parent)
      captured = nil

      with_routing do |set|
        set.draw do
          patch "recordings/:recording_id/placements/reorder", to: "recording_studio_attachable/placements#reorder"
          get "recordings/:recording_id/placements",
              to: "recording_studio_attachable/placements#index",
              as: :recording_placements
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_placement_action!, true) do
            @controller.stub(:protect_against_forgery?, false) do
              RecordingStudioAttachable::Services::ReorderPlacements.stub(
                :call,
                lambda { |**kwargs|
                  captured = kwargs
                  result
                }
              ) do
                patch :reorder, params: { recording_id: parent.id, ordered_recording_ids: %w[place-2 place-1] }
              end
            end
          end
        end
      end

      assert_redirected_to "/recordings/#{parent.id}/placements"
      assert_equal %w[place-2 place-1], captured[:ordered_recording_ids]
    end

    def test_create_uploads_to_the_library_when_no_existing_image_is_chosen
      parent = FakeRecording.new(id: "gallery-1", recordable_type: "Gallery")
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: parent)
      captured = nil

      with_routing do |set|
        set.draw do
          post "recordings/:recording_id/placements", to: "recording_studio_attachable/placements#create"
          get "recordings/:recording_id/placements",
              to: "recording_studio_attachable/placements#index",
              as: :recording_placements
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_placement_action!, true) do
            @controller.stub(:protect_against_forgery?, false) do
              RecordingStudioAttachable::Services::UploadToLibraryAndPlace.stub(
                :call,
                lambda { |**kwargs|
                  captured = kwargs
                  result
                }
              ) do
                post :create, params: { recording_id: parent.id, placement: { signed_blob_id: "signed-1" } }
              end
            end
          end
        end
      end

      assert_redirected_to "/recordings/#{parent.id}/placements"
      assert_equal "signed-1", captured[:signed_blob_id]
    end

    def test_destroy_removes_the_placement_not_the_image
      parent = FakeRecording.new(id: "gallery-1", recordable_type: "Gallery")
      placement = FakeRecording.new(
        id: "place-1",
        recordable_type: "RecordingStudioAttachable::Placement",
        parent_recording: parent
      )
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: placement)
      captured = nil

      with_routing do |set|
        set.draw do
          delete "placements/:id", to: "recording_studio_attachable/placements#destroy"
          get "recordings/:recording_id/placements",
              to: "recording_studio_attachable/placements#index",
              as: :recording_placements
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, placement) do
          @controller.stub(:authorize_placement_action!, true) do
            @controller.stub(:protect_against_forgery?, false) do
              RecordingStudioAttachable::Services::RemovePlacement.stub(
                :call,
                lambda { |**kwargs|
                  captured = kwargs
                  result
                }
              ) do
                delete :destroy, params: { id: placement.id }
              end
            end
          end
        end
      end

      assert_redirected_to "/recordings/#{parent.id}/placements"
      assert_equal parent, captured[:parent_recording]
      assert_equal placement, captured[:placement_recording]
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
