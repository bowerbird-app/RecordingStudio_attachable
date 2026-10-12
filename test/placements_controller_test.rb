# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/placements_controller"
require_relative "../lib/recording_studio_attachable/services/base_service"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/revise_placement_collection"

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

    def test_index_redirects_to_the_library_placements_screen
      parent = FakeRecording.new(id: "gallery-1", recordable_type: "Gallery")

      with_routing do |set|
        set.draw do
          get "recordings/:recording_id/placements", to: "recording_studio_attachable/placements#index"
        end

        @routes = set
        engine = Object.new
        engine.define_singleton_method(:recording_placements_path) do |item, **|
          "/recording_studio_library/recordings/#{item.id}/placements"
        end

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:library_engine, engine) do
            get :index, params: { recording_id: parent.id }
          end
        end
      end

      assert_redirected_to "/recording_studio_library/recordings/#{parent.id}/placements"
    end

    def test_update_saves_the_collection_and_redirects_see_other
      parent = FakeRecording.new(id: "gallery-1", recordable_type: "Gallery")
      result = Services::BaseService::Result.new(success: true, value: :saved)
      captured = nil

      with_routing do |set|
        set.draw do
          patch "recordings/:recording_id/placements", to: "recording_studio_attachable/placements#update"
        end

        @routes = set
        engine = Object.new
        engine.define_singleton_method(:recording_placements_path) do |item, **|
          "/recording_studio_library/recordings/#{item.id}/placements"
        end

        RecordingStudio::Recording.stub(:find, parent) do
          RecordingStudioAttachable::Authorization.stub(:authorize_placement!, true) do
            Services::RevisePlacementCollection.stub(:call, lambda { |**kwargs|
              captured = kwargs
              result
            }) do
              @controller.stub(:library_engine, engine) do
                @controller.stub(:protect_against_forgery?, false) do
                  patch :update, params: {
                    recording_id: parent.id,
                    redirect_mode: "return_to",
                    return_to: "/galleries/1/edit",
                    attachment_collection: {
                      signed_editor: "token",
                      rows: [{ recording_id: "place-1", caption: "Kiln light", credit: "Ada", alt_text: "Canister" }]
                    }
                  }
                end
              end
            end
          end
        end
      end

      assert_redirected_to "/galleries/1/edit"
      assert_equal 303, @response.status
      assert_equal "Saved.", flash[:notice]
      assert_equal parent, captured[:recording]
      assert_equal "Kiln light", captured[:params].dig(:attachment_collection, :rows, 0, :caption)
    end

    def test_controller_does_not_expose_library_mutate_actions
      refute_includes PlacementsController.public_instance_methods(false), :create
      refute_includes PlacementsController.public_instance_methods(false), :reorder
      refute_includes PlacementsController.public_instance_methods(false), :destroy
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
