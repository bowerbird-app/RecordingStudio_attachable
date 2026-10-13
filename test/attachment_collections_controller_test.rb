# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_attachable/application_controller"
require_relative "../app/controllers/recording_studio_attachable/attachment_collections_controller"
require_relative "../app/queries/recording_studio_attachable/queries/for_recording"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/revise_attachment_metadata"
require_relative "../app/services/recording_studio_attachable/services/revise_attachment_collection"
require_relative "../lib/recording_studio_attachable/services/base_service"

module RecordingStudioAttachable
  class AttachmentCollectionsControllerTest < ActionController::TestCase
    FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)
    SheetSnapshot = Struct.new(
      :id, :name, :description, :caption, :credit, :alt_text, :attachment_kind,
      :original_filename, :content_type, :byte_size, :file, keyword_init: true
    )
    SheetFile = Struct.new(:blob)

    def setup
      @controller = AttachmentCollectionsController.new
      ensure_recording_lookup!
    end

    def test_update_redirects_see_other_to_return_to_with_saved_notice
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      result = Services::BaseService::Result.new(success: true, value: parent)
      captured = nil

      with_routing do |set|
        set.draw do
          patch "/recordings/:recording_id/attachment_collection",
                to: "recording_studio_attachable/attachment_collections#update"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_attachment_action!, true) do
            Services::ReviseAttachmentCollection.stub(:call, lambda { |**kwargs|
              captured = kwargs
              result
            }) do
              @controller.stub(:protect_against_forgery?, false) do
                patch :update, params: {
                  recording_id: parent.id,
                  redirect_mode: "return_to",
                  return_to: "/attachment_editor",
                  attachment_collection: {
                    signed_editor: "token",
                    fields: ["caption"],
                    rows: [{ recording_id: "image-1", caption: "Pier light", alt_text: "Sneaky" }]
                  }
                }
              end
            end
          end
        end
      end

      assert_redirected_to "/attachment_editor"
      assert_equal 303, @response.status
      assert_equal "Saved.", flash[:notice]
      assert_equal parent, captured[:recording]
      assert_equal "token", captured[:params].dig(:attachment_collection, :signed_editor)
      assert_nil captured[:params].dig(:attachment_collection, :fields)
      assert_equal "Pier light", captured[:params].dig(:attachment_collection, :rows, 0, :caption)
    end

    def test_slide_save_answers_json_and_does_not_redirect
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      result = Services::BaseService::Result.new(success: true, value: parent)

      with_routing do |set|
        set.draw do
          patch "/recordings/:recording_id/attachment_collection",
                to: "recording_studio_attachable/attachment_collections#update"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_attachment_action!, true) do
            Services::ReviseAttachmentCollection.stub(:call, ->(**) { result }) do
              @controller.stub(:protect_against_forgery?, false) do
                @request.headers["Accept"] = "application/json"
                patch :update, params: {
                  recording_id: parent.id,
                  stay: "slide",
                  redirect_mode: "return_to",
                  return_to: "/attachment_editor",
                  attachment_collection: { signed_editor: "token", rows: [{ recording_id: "image-1", caption: "Pier light" }] }
                }, xhr: true
              end
            end
          end
        end
      end

      assert_response :ok
      assert_equal({ "saved" => true }, JSON.parse(@response.body))
      assert_nil flash[:notice]
    end

    def test_slide_save_without_the_ajax_header_still_redirects
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      result = Services::BaseService::Result.new(success: true, value: parent)

      with_routing do |set|
        set.draw do
          patch "/recordings/:recording_id/attachment_collection",
                to: "recording_studio_attachable/attachment_collections#update"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_attachment_action!, true) do
            Services::ReviseAttachmentCollection.stub(:call, ->(**) { result }) do
              @controller.stub(:protect_against_forgery?, false) do
                @request.headers["Accept"] = "application/json"
                patch :update, params: {
                  recording_id: parent.id,
                  stay: "slide",
                  redirect_mode: "return_to",
                  return_to: "/attachment_editor",
                  attachment_collection: { signed_editor: "token", rows: [] }
                }
              end
            end
          end
        end
      end

      assert_redirected_to "/attachment_editor"
      assert_equal 303, @response.status
    end

    def test_slide_save_returns_the_error_without_redirecting
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      result = Services::BaseService::Result.new(success: false, error: "Caption is too long")

      with_routing do |set|
        set.draw do
          patch "/recordings/:recording_id/attachment_collection",
                to: "recording_studio_attachable/attachment_collections#update"
        end

        @routes = set

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_attachment_action!, true) do
            Services::ReviseAttachmentCollection.stub(:call, ->(**) { result }) do
              @controller.stub(:protect_against_forgery?, false) do
                @request.headers["Accept"] = "application/json"
                patch :update, params: {
                  recording_id: parent.id,
                  stay: "slide",
                  attachment_collection: { signed_editor: "token", rows: [] }
                }, xhr: true
              end
            end
          end
        end
      end

      assert_response :unprocessable_entity
      assert_equal({ "saved" => false, "error" => "Caption is too long" }, JSON.parse(@response.body))
    end

    def test_update_without_return_to_goes_to_the_attachment_index
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      result = Services::BaseService::Result.new(success: true, value: parent)

      with_routing do |set|
        set.draw do
          patch "/recordings/:recording_id/attachment_collection",
                to: "recording_studio_attachable/attachment_collections#update"
        end

        @routes = set

        @controller.define_singleton_method(:recording_attachments_path) do |recording|
          "/recordings/#{recording.id}/attachments"
        end

        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_attachment_action!, true) do
            Services::ReviseAttachmentCollection.stub(:call, ->(**) { result }) do
              @controller.stub(:protect_against_forgery?, false) do
                patch :update, params: {
                  recording_id: parent.id,
                  attachment_collection: { signed_editor: "token", rows: [] }
                }
              end
            end
          end
        end
      end

      assert_redirected_to "/recordings/parent-1/attachments"
      assert_equal 303, @response.status
      assert_equal "Saved.", flash[:notice]
    end

    def test_update_saves_a_linked_sheet_without_passing_the_options_again
      parent = sheet_parent
      first_file = sheet_file("image-1", parent, caption: "Pier light")
      second_file = sheet_file("image-2", parent, caption: "Right")
      first = sheet_pointer("member-1", parent)
      second = sheet_pointer("member-2", parent)
      parent.sheet_children.replace([first, second])
      linked = [sheet_link(first, first_file), sheet_link(second, second_file)]
      @sheet_events = []
      collection = nil

      with_sheet_doubles([sheet_file("owned-1", parent, caption: "Owned")], first_file, second_file, first, second) do
        collection = linked_collection(parent, linked)
        patch_collection(parent, collection.signed_editor, [
                           { recording_id: "member-2", order: "1", caption: "Right" },
                           { recording_id: "member-1", order: "2", caption: "Moved" }
                         ])
      end

      assert_redirected_to "/attachment_editor"
      assert_equal 303, @response.status
      assert_equal "Saved.", flash[:notice]
      assert_equal([%w[member-2 member-1]], parent.reorders.map { |call| call[:ordered_recording_ids] })
      assert_equal([%w[image-1 Moved]], @sheet_events.map { |event| [event[:recording].id, event[:recordable].caption] })

      rebuilt = with_sheet_doubles([sheet_file("owned-1", parent, caption: "Owned")], first_file, second_file, first, second) do
        RecordingStudioAttachable::AttachmentCollection.from_params(
          recording: parent,
          params: { signed_editor: collection.signed_editor, rows: [] }
        )
      end
      assert_equal "Remove from here", rebuilt.remove_label
      assert_equal "/pointers/member-1", rebuilt.remove_path.call(rebuilt.rows.first, {})
      assert_equal "image-1", rebuilt.rows.first.recording.id
    end

    def test_update_rejects_a_foreign_member_and_a_tampered_token
      parent = sheet_parent
      photo = sheet_file("image-1", parent, caption: "Pier light")
      member = sheet_pointer("member-1", parent)
      member.define_singleton_method(:parent_recording_id) { "other-parent" }
      parent.sheet_children.replace([member])
      @sheet_events = []
      collection = with_sheet_doubles([], photo, member) do
        linked_collection(parent, [sheet_link(member, photo)])
      end
      tampered = collection.signed_editor.sub(/.\z/, collection.signed_editor.end_with?("a") ? "b" : "a")

      with_sheet_doubles([], photo, member) do
        patch_collection(parent, collection.signed_editor, [{ recording_id: "member-1", order: "1", caption: "Moved" }])
      end

      assert_redirected_to "/attachment_editor"
      assert_equal RecordingStudioAttachable::AttachmentCollection::GONE, flash[:alert]
      assert_empty @sheet_events
      assert_empty parent.reorders

      with_sheet_doubles([], photo, member) do
        patch_collection(parent, tampered, [{ recording_id: "member-1", caption: "Moved" }])
      end

      assert_equal RecordingStudioAttachable::AttachmentCollection::STALE_FORM, flash[:alert]
      assert_empty @sheet_events
    end

    private

    def ensure_recording_lookup!
      studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
      studio.const_set(:Recording, Class.new) unless defined?(RecordingStudio::Recording)
      return if RecordingStudio::Recording.respond_to?(:find)

      RecordingStudio::Recording.define_singleton_method(:find) { |_id| raise NotImplementedError }
    end

    def sheet_parent
      parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace")
      children = []
      reorders = []
      parent.define_singleton_method(:sheet_children) { children }
      parent.define_singleton_method(:reorders) { reorders }
      parent.define_singleton_method(:recording_studio_orderable_children) { children }
      parent.define_singleton_method(:recording_studio_orderable_reorder!) { |**kwargs| reorders << kwargs }
      parent
    end

    def sheet_pointer(id, parent)
      recording = FakeRecording.new(id: id, recordable_type: "Pointer")
      recording.define_singleton_method(:parent_recording) { parent }
      recording.define_singleton_method(:parent_recording_id) { parent.id }
      recording.define_singleton_method(:to_global_id) { "gid://test/Recording/#{id}" }
      recording.define_singleton_method(:created_at) { Time.utc(2026, 1, 1) }
      recording
    end

    def sheet_file(id, parent, caption:)
      recordable = SheetSnapshot.new(
        id: "recordable-#{id}", name: id, description: nil, caption: caption, credit: nil, alt_text: nil,
        attachment_kind: "image", original_filename: "#{id}.png", content_type: "image/png", byte_size: 12,
        file: SheetFile.new(Object.new)
      )
      recording = FakeRecording.new(id: id, recordable_type: "RecordingStudioAttachable::Attachment")
      recording.define_singleton_method(:recordable) { recordable }
      recording.define_singleton_method(:parent_recording) { parent }
      recording.define_singleton_method(:parent_recording_id) { parent.id }
      recording.define_singleton_method(:root_recording) { parent }
      recording.define_singleton_method(:to_global_id) { "gid://test/Recording/#{id}" }
      recording.define_singleton_method(:created_at) { Time.utc(2026, 1, 1) }
      recording
    end

    def sheet_link(member, attachment_recording)
      Struct.new(:member, :attachment_recording).new(member, attachment_recording)
    end

    def linked_collection(parent, items)
      RecordingStudioAttachable::AttachmentCollection.for(
        recording: parent,
        association: :images,
        fields: [:caption],
        sortable: true,
        items: items,
        return_to: "/attachment_editor",
        remove_label: "Remove from here",
        remove_path: ->(row, _params) { "/pointers/#{row.member.id}" }
      )
    end

    def with_sheet_doubles(owned, *located, &)
      query = Object.new
      query.define_singleton_method(:unpaged) { owned }
      registry = located.to_h { |recording| [recording.to_global_id, recording] }
      RecordingStudioAttachable::Queries::ForRecording.stub(:new, ->(**) { query }) do
        GlobalID::Locator.stub(:locate, ->(gid) { registry.fetch(gid) { raise ActiveRecord::RecordNotFound } }) do
          RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
            ensure_sheet_attachment!
            RecordingStudioAttachable::Attachment.stub(:build_from_blob, method(:built_sheet)) do
              RecordingStudio.stub(:record!, method(:capture_sheet_event), &)
            end
          end
        end
      end
    end

    def patch_collection(parent, token, rows)
      with_routing do |set|
        set.draw do
          patch "/recordings/:recording_id/attachment_collection",
                to: "recording_studio_attachable/attachment_collections#update"
        end
        @routes = set
        RecordingStudio::Recording.stub(:find, parent) do
          @controller.stub(:authorize_attachment_action!, true) do
            @controller.stub(:protect_against_forgery?, false) do
              patch :update, params: {
                recording_id: parent.id,
                redirect_mode: "return_to",
                return_to: "/attachment_editor",
                attachment_collection: { signed_editor: token, rows: rows }
              }
            end
          end
        end
      end
    end

    def built_sheet(**kwargs)
      SheetSnapshot.new(
        id: "snapshot", name: kwargs[:name], description: kwargs[:description], caption: kwargs[:caption],
        credit: kwargs[:credit], alt_text: kwargs[:alt_text], attachment_kind: "image",
        original_filename: "photo.png", content_type: "image/png", byte_size: 12, file: nil
      )
    end

    def capture_sheet_event(**kwargs)
      @sheet_events << kwargs
      Struct.new(:recording).new(kwargs[:recording])
    end

    def ensure_sheet_attachment!
      klass = sheet_attachment_class
      return if klass.respond_to?(:build_from_blob)

      klass.define_singleton_method(:build_from_blob) { |**| raise NotImplementedError }
    end

    def sheet_attachment_class
      RecordingStudioAttachable::Attachment
    rescue NameError
      RecordingStudioAttachable.const_set(:Attachment, Class.new)
    end
  end
end
