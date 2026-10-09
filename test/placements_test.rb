# frozen_string_literal: true

require "test_helper"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/find_or_create_library"
require_relative "../app/services/recording_studio_attachable/services/place_library_image"
require_relative "../app/services/recording_studio_attachable/services/remove_placement"
require_relative "../app/services/recording_studio_attachable/services/reorder_placements"
require_relative "../app/services/recording_studio_attachable/services/resolve_placements"
require_relative "../app/services/recording_studio_attachable/services/placement_usage"
require_relative "../app/services/recording_studio_attachable/services/purge_placements"
require_relative "../app/services/recording_studio_attachable/services/upload_to_library_and_place"
require_relative "../app/services/recording_studio_attachable/services/record_attachment_upload"

class PlacementsTest < Minitest::Test
  PlacementRecordable = Struct.new(:id, :attachment_recording_id, keyword_init: true)

  Recording = Struct.new(:id, :recordable_type, :parent_recording_id, :root_recording_id, :root_recording, :recordable,
                         :trashed_at, :parent_recording, :child_recordings, :placed, keyword_init: true) do
    attr_accessor :trashed_with, :destroyed, :reordered_with, :appended

    def record(_type, parent_recording:, **)
      placement = PlacementsTest::PlacementRecordable.new
      yield placement if block_given?
      child = Recording.new(
        id: "place-#{Array(placed).size + 1}",
        recordable_type: "RecordingStudioAttachable::Placement",
        parent_recording_id: parent_recording.id,
        root_recording_id: root_recording_id,
        recordable: placement
      )
      self.placed = Array(placed) + [child]
      child
    end

    def recording_studio_orderable_append!(child, actor:)
      self.appended = [child, actor]
      child
    end

    def recording_studio_orderable_reorder!(ordered_recording_ids:, actor:)
      self.reordered_with = [ordered_recording_ids, actor]
    end

    def recording_studio_orderable_children
      Array(placed)
    end

    def recording_studio_trashable_trash!(actor:, impersonator: nil)
      self.trashed_with = [actor, impersonator]
      self.trashed_at = Time.now
    end

    def destroy!
      self.destroyed = true
    end
  end

  Attachment = Struct.new(:id, :name, :caption, :credit, :alt_text, keyword_init: true)
  ParentRecordable = Struct.new(:title, :name, keyword_init: true)

  def setup
    stub_placement_class!
    stub_authorization!
  end

  def teardown
    restore_authorization!
    restore_placement_class!
  end

  def test_place_library_image_records_a_pointer_and_appends_order
    root = Recording.new(id: "root-1", recordable_type: "Workspace")
    library = Recording.new(id: "lib-1", recordable_type: "RecordingStudioAttachable::Library", parent_recording_id: "root-1")
    parent = Recording.new(id: "gallery-1", recordable_type: "Gallery", root_recording_id: "root-1", root_recording: root)
    attachment = Recording.new(
      id: "att-1",
      recordable_type: "RecordingStudioAttachable::Attachment",
      parent_recording_id: "lib-1",
      root_recording_id: "root-1",
      recordable: Attachment.new(id: "snap-1", name: "Hero")
    )

    with_library(library) do
      result = RecordingStudioAttachable::Services::PlaceLibraryImage.call(
        parent_recording: parent,
        attachment_recording: attachment,
        actor: :ada
      )

      assert result.success?
      assert_equal "att-1", result.value.recordable.attachment_recording_id
      assert_equal [result.value, :ada], parent.appended
    end
  end

  def test_place_library_image_refuses_another_workspace
    root = Recording.new(id: "root-1", recordable_type: "Workspace")
    other = Recording.new(id: "root-2", recordable_type: "Workspace")
    library = Recording.new(id: "lib-1", recordable_type: "RecordingStudioAttachable::Library", parent_recording_id: "root-1")
    parent = Recording.new(id: "gallery-1", recordable_type: "Gallery", root_recording_id: "root-1", root_recording: root)
    attachment = Recording.new(
      id: "att-1",
      recordable_type: "RecordingStudioAttachable::Attachment",
      parent_recording_id: "lib-2",
      root_recording_id: "root-2",
      root_recording: other,
      recordable: Attachment.new(id: "snap-1", name: "Hero")
    )

    with_library(library) do
      result = RecordingStudioAttachable::Services::PlaceLibraryImage.call(
        parent_recording: parent,
        attachment_recording: attachment,
        actor: :ada
      )

      assert result.failure?
      assert_match(/another workspace/, result.error)
    end
  end

  def test_place_library_image_refuses_a_photo_that_is_not_in_the_library
    root = Recording.new(id: "root-1", recordable_type: "Workspace")
    library = Recording.new(id: "lib-1", recordable_type: "RecordingStudioAttachable::Library", parent_recording_id: "root-1")
    parent = Recording.new(id: "gallery-1", recordable_type: "Gallery", root_recording_id: "root-1", root_recording: root)
    attachment = Recording.new(
      id: "att-1",
      recordable_type: "RecordingStudioAttachable::Attachment",
      parent_recording_id: "page-1",
      root_recording_id: "root-1",
      recordable: Attachment.new(id: "snap-1", name: "Page photo")
    )

    with_library(library) do
      result = RecordingStudioAttachable::Services::PlaceLibraryImage.call(
        parent_recording: parent,
        attachment_recording: attachment,
        actor: :ada
      )

      assert result.failure?
      assert_match(/not in this workspace library/, result.error)
    end
  end

  def test_resolve_skips_trashed_images_and_keeps_the_placement
    root = Recording.new(id: "root-1", recordable_type: "Workspace")
    library = Recording.new(id: "lib-1", recordable_type: "RecordingStudioAttachable::Library", parent_recording_id: "root-1")
    live_attachment = Recording.new(
      id: "att-live",
      recordable_type: "RecordingStudioAttachable::Attachment",
      parent_recording_id: "lib-1",
      root_recording_id: "root-1",
      recordable: Attachment.new(id: "snap-live", name: "Live")
    )
    trashed_attachment = Recording.new(
      id: "att-trash",
      recordable_type: "RecordingStudioAttachable::Attachment",
      parent_recording_id: "lib-1",
      root_recording_id: "root-1",
      trashed_at: Time.now,
      recordable: Attachment.new(id: "snap-trash", name: "Trashed")
    )
    live_placement = Recording.new(
      id: "place-1",
      recordable_type: "RecordingStudioAttachable::Placement",
      recordable: PlacementRecordable.new(attachment_recording_id: "att-live")
    )
    trash_placement = Recording.new(
      id: "place-2",
      recordable_type: "RecordingStudioAttachable::Placement",
      recordable: PlacementRecordable.new(attachment_recording_id: "att-trash")
    )
    parent = Recording.new(
      id: "gallery-1",
      recordable_type: "Gallery",
      root_recording_id: "root-1",
      root_recording: root,
      placed: [live_placement, trash_placement]
    )
    attachments = { "att-live" => live_attachment, "att-trash" => trashed_attachment }

    with_library(library) do
      recording_class.stub(:includes, recording_class) do
        recording_class.stub(:find_by, ->(id:) { attachments[id] }) do
          resolved = RecordingStudioAttachable::Placements.resolve(parent)

          assert_equal 1, resolved.size
          assert_equal "place-1", resolved.first.placement_recording.id
          assert_equal "Live", resolved.first.attachment.name
        end
      end
    end
  end

  def test_remove_placement_trashes_the_pointer_and_leaves_the_image
    parent = Recording.new(id: "gallery-1", recordable_type: "Gallery")
    placement = Recording.new(
      id: "place-1",
      recordable_type: "RecordingStudioAttachable::Placement",
      parent_recording_id: "gallery-1",
      recordable: PlacementRecordable.new(attachment_recording_id: "att-1")
    )

    result = RecordingStudioAttachable::Services::RemovePlacement.call(
      parent_recording: parent,
      placement_recording: placement,
      actor: :ada,
      impersonator: :imp
    )

    assert result.success?
    assert_equal %i[ada imp], placement.trashed_with
    assert_nil placement.destroyed
  end

  def test_remove_placement_destroys_when_trashable_is_unavailable
    parent = Recording.new(id: "gallery-1", recordable_type: "Gallery")
    placement = Object.new
    placement.define_singleton_method(:recordable_type) { "RecordingStudioAttachable::Placement" }
    placement.define_singleton_method(:parent_recording_id) { "gallery-1" }
    placement.define_singleton_method(:destroy!) { @destroyed = true }
    placement.define_singleton_method(:destroyed) { @destroyed }

    result = RecordingStudioAttachable::Services::RemovePlacement.call(
      parent_recording: parent,
      placement_recording: placement,
      actor: :ada
    )

    assert result.success?
    assert placement.destroyed
  end

  def test_reorder_uses_orderable
    parent = Recording.new(id: "gallery-1", recordable_type: "Gallery")

    result = RecordingStudioAttachable::Services::ReorderPlacements.call(
      parent_recording: parent,
      ordered_recording_ids: %w[place-2 place-1],
      actor: :ada
    )

    assert result.success?
    assert_equal [%w[place-2 place-1], :ada], parent.reordered_with
  end

  def test_usage_names_the_places
    attachment = Recording.new(
      id: "att-1",
      recordable_type: "RecordingStudioAttachable::Attachment",
      recordable: Attachment.new(id: "snap-1")
    )
    parent = Recording.new(
      id: "gallery-1",
      recordable_type: "Gallery",
      recordable: ParentRecordable.new(title: "Kiln shots")
    )
    placement = Recording.new(
      id: "place-1",
      recordable_type: "RecordingStudioAttachable::Placement",
      parent_recording: parent,
      recordable: PlacementRecordable.new(id: "row-1", attachment_recording_id: "att-1")
    )

    RecordingStudioAttachable::Placement.stub(:where, placement_ids_relation(%w[row-1])) do
      relation = [placement]
      relation.define_singleton_method(:includes) { |*| relation }
      relation.define_singleton_method(:order) { |*| relation }
      recording_class.stub(:where, relation) do
        usages = RecordingStudioAttachable::Placements.usage_for(attachment)

        assert_equal 1, usages.size
        assert_equal "Kiln shots", usages.first.label
        assert_equal parent, usages.first.parent_recording
      end
    end
  end

  def test_purge_destroys_placements_for_the_image
    attachment = Recording.new(id: "att-1", recordable_type: "RecordingStudioAttachable::Attachment")
    placement = Recording.new(
      id: "place-1",
      recordable_type: "RecordingStudioAttachable::Placement",
      recordable: PlacementRecordable.new(id: "row-1")
    )
    recordings = [placement]
    recordings.define_singleton_method(:to_a) { recordings }

    RecordingStudioAttachable::Placement.stub(:where, placement_ids_relation(%w[row-1])) do
      recording_class.stub(:unscoped, recording_class) do
        recording_class.stub(:where, recordings) do
          result = RecordingStudioAttachable::Services::PurgePlacements.call(attachment_recording: attachment)

          assert result.success?
          assert placement.destroyed
        end
      end
    end
  end

  def test_upload_to_library_and_place_uploads_then_places
    root = Recording.new(id: "root-1", recordable_type: "Workspace")
    library = Recording.new(id: "lib-1", recordable_type: "RecordingStudioAttachable::Library", parent_recording_id: "root-1")
    parent = Recording.new(id: "gallery-1", recordable_type: "Gallery", root_recording_id: "root-1", root_recording: root)
    uploaded = Recording.new(
      id: "att-new",
      recordable_type: "RecordingStudioAttachable::Attachment",
      parent_recording_id: "lib-1",
      root_recording_id: "root-1",
      recordable: Attachment.new(id: "snap-new", name: "New")
    )

    with_library(library) do
      RecordingStudioAttachable::Services::FindOrCreateLibrary.stub(:call, success_result(library)) do
        RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(
          :call,
          lambda { |**kwargs|
            assert_equal library, kwargs[:parent_recording]
            assert_equal "signed-1", kwargs[:signed_blob_id]
            success_result(uploaded)
          }
        ) do
          result = RecordingStudioAttachable::Services::UploadToLibraryAndPlace.call(
            parent_recording: parent,
            signed_blob_id: "signed-1",
            actor: :ada
          )

          assert result.success?
          assert_equal "att-new", result.value.recordable.attachment_recording_id
        end
      end
    end
  end

  def test_library_placement_recording_methods_delegate_to_services
    parent = Recording.new(id: "gallery-1", recordable_type: "Gallery")
    parent.extend(RecordingStudio::Capabilities::LibraryPlacement::RecordingMethods)
    parent.define_singleton_method(:assert_capability!) { |*| true }

    RecordingStudioAttachable::Services::PlaceLibraryImage.stub(:call, success_result(:placed)) do
      assert_equal :placed, parent.place_library_image(attachment_recording: :photo)
    end
    RecordingStudioAttachable::Services::UploadToLibraryAndPlace.stub(:call, success_result(:uploaded)) do
      assert_equal :uploaded, parent.upload_to_library_and_place(signed_blob_id: "signed")
    end
    RecordingStudioAttachable::Services::ResolvePlacements.stub(:call, success_result([:item])) do
      assert_equal [:item], parent.library_placements
    end
    RecordingStudioAttachable::Services::ReorderPlacements.stub(:call, success_result(parent)) do
      assert_equal parent, parent.reorder_library_placements!(ordered_recording_ids: %w[a])
    end
    RecordingStudioAttachable::Services::RemovePlacement.stub(:call, success_result(:removed)) do
      assert_equal :removed, parent.remove_library_placement(placement_recording: :row)
    end
  end

  def test_library_placement_to_delegates_to_include_for
    captured = nil
    RecordingStudio::Capabilities.stub(:include_for, lambda { |name, **options|
      captured = [name, options]
      Module.new
    }) do
      RecordingStudio::Capabilities::LibraryPlacement.to
    end

    assert_equal [:library_placement, {}], captured
  end

  def test_duplicating_a_host_copies_the_pointer_not_the_file
    placement = PlacementRecordable.new(attachment_recording_id: "att-shared")
    copy = placement.dup

    assert_equal "att-shared", copy.attachment_recording_id
    refute_same placement, copy
  end

  def test_place_label_falls_back_to_title_then_type
    titled = Recording.new(recordable: ParentRecordable.new(title: "Kiln shots"))
    named = Recording.new(recordable: ParentRecordable.new(name: "Untitled kiln"))
    typed = Recording.new(recordable_type: "Gallery")

    assert_equal "Kiln shots", RecordingStudioAttachable::Placements.place_label(titled)
    assert_equal "Untitled kiln", RecordingStudioAttachable::Placements.place_label(named)
    assert_equal "Gallery", RecordingStudioAttachable::Placements.place_label(typed)
  end

  def test_storage_release_purges_placements_for_attachments
    recording = Object.new
    recording.extend(RecordingStudioAttachable::StorageRelease)
    recording.define_singleton_method(:recordable_type) { "RecordingStudioAttachable::Attachment" }
    captured = nil
    RecordingStudioAttachable::Placements.stub(:purge_for, ->(value) { captured = value }) do
      recording.recording_studio_attachable_purge_placements
    end

    assert_same recording, captured
  end

  private

  def stub_placement_class!
    return if defined?(RecordingStudioAttachable::Placement)

    RecordingStudioAttachable.const_set(
      :Placement,
      Class.new do
        attr_accessor :attachment_recording_id

        def self.where(*)
          Struct.new(:pluck).new([])
        end
      end
    )
    @created_placement_stub = true
  end

  def restore_placement_class!
    return unless @created_placement_stub && RecordingStudioAttachable.const_defined?(:Placement)

    RecordingStudioAttachable.send(:remove_const, :Placement)
  end

  def stub_authorization!
    auth = RecordingStudioAttachable::Authorization
    @original_assert_placement = auth.method(:assert_placement_enabled!)
    @original_authorize_placement = auth.method(:authorize_placement!)
    auth.define_singleton_method(:assert_placement_enabled!) { |**| true }
    auth.define_singleton_method(:authorize_placement!) { |**| true }
    recording_class
  end

  def restore_authorization!
    auth = RecordingStudioAttachable::Authorization
    auth.define_singleton_method(:assert_placement_enabled!, @original_assert_placement) if @original_assert_placement
    auth.define_singleton_method(:authorize_placement!, @original_authorize_placement) if @original_authorize_placement
  end

  def recording_class
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.const_set(:Recording, Class.new) unless studio.const_defined?(:Recording)
    klass = studio::Recording
    %i[where includes find_by unscoped].each do |method_name|
      next if klass.respond_to?(method_name)

      klass.define_singleton_method(method_name) { |*| klass }
    end
    klass
  end

  def placement_ids_relation(ids)
    relation = Object.new
    relation.define_singleton_method(:pluck) { |*| ids }
    relation
  end

  def with_library(library, &)
    recording_class.stub(:where, [library], &)
  end

  def success_result(value)
    RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: value)
  end
end
