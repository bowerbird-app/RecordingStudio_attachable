# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/reorder_placements"
require_relative "../../app/services/recording_studio_attachable/services/revise_attachment_metadata"
require_relative "../../app/services/recording_studio_attachable/services/revise_placement_collection"

class RevisePlacementCollectionTest < Minitest::Test
  Parent = Struct.new(:id)

  def test_returns_reordered_when_the_sheet_has_new_order
    parent = Parent.new("gallery-1")
    sheet = Object.new
    sheet.define_singleton_method(:placement?) { true }
    sheet.define_singleton_method(:reorder_ids) { %w[place-2 place-1] }
    sheet.define_singleton_method(:revisions) { [] }
    captured = nil

    RecordingStudioAttachable::AttachmentCollection.stub(:from_params, sheet) do
      RecordingStudioAttachable::Services::ReorderPlacements.stub(
        :call,
        lambda { |**kwargs|
          captured = kwargs
          RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: parent)
        }
      ) do
        result = RecordingStudioAttachable::Services::RevisePlacementCollection.call(
          recording: parent,
          params: { attachment_collection: { signed_editor: "token" } },
          actor: :user
        )

        assert_predicate result, :success?
        assert_equal :reordered, result.value
        assert_equal %w[place-2 place-1], captured[:ordered_recording_ids]
      end
    end
  end

  def test_skips_reorder_when_the_order_did_not_change
    parent = Parent.new("gallery-1")
    sheet = Object.new
    sheet.define_singleton_method(:placement?) { true }
    sheet.define_singleton_method(:reorder_ids) { nil }
    sheet.define_singleton_method(:revisions) { [] }

    RecordingStudioAttachable::AttachmentCollection.stub(:from_params, sheet) do
      result = RecordingStudioAttachable::Services::RevisePlacementCollection.call(
        recording: parent,
        params: { attachment_collection: { signed_editor: "token" } }
      )

      assert_predicate result, :success?
      assert_equal parent, result.value
    end
  end

  def test_revises_the_library_photo_then_reorders
    parent = Parent.new("gallery-1")
    photo = Object.new
    revision = Struct.new(:recording, :changes).new(photo, { caption: "Dawn" })
    sheet = Object.new
    sheet.define_singleton_method(:placement?) { true }
    sheet.define_singleton_method(:revisions) { [revision] }
    sheet.define_singleton_method(:reorder_ids) { %w[place-2 place-1] }
    captured = {}

    RecordingStudioAttachable::AttachmentCollection.stub(:from_params, sheet) do
      RecordingStudioAttachable::Services::ReviseAttachmentMetadata.stub(
        :call,
        lambda { |**kwargs|
          captured[:revise] = kwargs
          RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: photo)
        }
      ) do
        RecordingStudioAttachable::Services::ReorderPlacements.stub(
          :call,
          lambda { |**kwargs|
            captured[:reorder] = kwargs
            RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: parent)
          }
        ) do
          result = RecordingStudioAttachable::Services::RevisePlacementCollection.call(
            recording: parent,
            params: { attachment_collection: { signed_editor: "token" } },
            actor: :user
          )

          assert_predicate result, :success?
          assert_equal :saved, result.value
          assert_equal photo, captured[:revise][:attachment_recording]
          assert_equal "Dawn", captured[:revise][:caption]
          assert_equal %w[place-2 place-1], captured[:reorder][:ordered_recording_ids]
        end
      end
    end
  end

  def test_rejects_a_non_placement_sheet
    sheet = Object.new
    sheet.define_singleton_method(:placement?) { false }

    RecordingStudioAttachable::AttachmentCollection.stub(:from_params, sheet) do
      result = RecordingStudioAttachable::Services::RevisePlacementCollection.call(
        recording: Parent.new("gallery-1"),
        params: { attachment_collection: { signed_editor: "token" } }
      )

      assert_predicate result, :failure?
      assert_equal RecordingStudioAttachable::AttachmentCollection::STALE_FORM, result.error
    end
  end
end
