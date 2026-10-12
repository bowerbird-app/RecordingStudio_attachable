# frozen_string_literal: true

require "test_helper"

class PlacementsTest < Minitest::Test
  Recording = Struct.new(:id, :recordable_type, :recordable, keyword_init: true)
  ParentRecordable = Struct.new(:title, :name, keyword_init: true)

  def test_place_library_image_delegates_to_library
    captured = nil
    RecordingStudioLibrary.stub(:place!, lambda { |holder, item, **kwargs|
      captured = [holder, item, kwargs]
      :placed
    }) do
      result = RecordingStudioAttachable.place_library_image(:gallery, attachment_recording: :photo, actor: :ada)
      assert_equal :placed, result
      assert_equal [:gallery, :photo, { actor: :ada }], captured
    end
  end

  def test_reorder_and_remove_delegate
    RecordingStudioLibrary.stub(:reorder!, :reordered) do
      assert_equal :reordered, RecordingStudioAttachable.reorder_library_placements!(:gallery, ordered_recording_ids: %w[a b], actor: :ada)
    end
    RecordingStudioLibrary.stub(:remove!, :removed) do
      assert_equal :removed, RecordingStudioAttachable.remove_library_placement(:gallery, placement_recording: :row, actor: :ada)
    end
  end

  def test_resolve_passes_a_nil_actor_through
    captured = nil
    RecordingStudioLibrary.stub(:resolve, lambda { |_holder, **kwargs|
      captured = kwargs
      []
    }) do
      RecordingStudioAttachable::Placements.resolve(:gallery, actor: nil)
    end

    assert_equal false, captured.fetch(:include_trashed)
    assert_nil captured.fetch(:actor)
  end

  def test_resolve_omitted_actor_stays_nil_without_current
    skip if defined?(Current)

    captured = nil
    RecordingStudioLibrary.stub(:resolve, lambda { |_holder, **kwargs|
      captured = kwargs
      []
    }) do
      RecordingStudioAttachable::Placements.resolve(:gallery)
    end

    assert_nil captured.fetch(:actor)
  end

  def test_resolve_wraps_attachment_aliases
    item = Object.new
    recording = Object.new
    placement = Object.new
    adapter = Object.new
    entry = RecordingStudioLibrary::Placements::Resolved.new(
      placement_recording: placement,
      item_recording: recording,
      item: item,
      adapter: adapter
    )

    RecordingStudioLibrary.stub(:resolve, [entry]) do
      resolved = RecordingStudioAttachable::Placements.resolve(:gallery, actor: :ada)

      assert_equal 1, resolved.size
      assert_equal recording, resolved.first.attachment_recording
      assert_equal item, resolved.first.attachment
      assert_equal recording, resolved.first.item_recording
      assert_equal adapter, resolved.first.adapter
    end
  end

  def test_library_placement_recording_methods_delegate
    parent = Object.new
    parent.extend(RecordingStudio::Capabilities::LibraryPlacement::RecordingMethods)
    parent.define_singleton_method(:assert_capability!) { |*| true }
    parent.define_singleton_method(:recordable_type) { "Gallery" }

    RecordingStudioAttachable.stub(:place_library_image, :placed) do
      assert_equal :placed, parent.place_library_image(attachment_recording: :photo)
    end
    RecordingStudioAttachable.stub(:upload_to_library_and_place, :uploaded) do
      assert_equal :uploaded, parent.upload_to_library_and_place(signed_blob_id: "signed")
    end
    RecordingStudioAttachable::Placements.stub(:resolve, [:item]) do
      assert_equal [:item], parent.library_placements
    end
    RecordingStudioAttachable.stub(:reorder_library_placements!, parent) do
      assert_equal parent, parent.reorder_library_placements!(ordered_recording_ids: %w[a])
    end
    RecordingStudioAttachable.stub(:remove_library_placement, :removed) do
      assert_equal :removed, parent.remove_library_placement(placement_recording: :row)
    end
  end

  def test_library_placement_to_includes_placeable_and_the_alias
    calls = []
    RecordingStudio::Capabilities.stub(:include_for, lambda { |name, **options|
      calls << [name, options]
      Module.new
    }) do
      RecordingStudio::Capabilities::LibraryPlacement.to(
        types: ["RecordingStudioAttachable::Attachment"],
        libraries: [:default]
      )
    end

    assert_includes calls, [:placeable, { types: ["RecordingStudioAttachable::Attachment"], libraries: [:default] }]
    assert_includes calls, [:library_placement, {}]
  end

  def test_place_label_falls_back_to_title_then_type
    titled = Recording.new(recordable: ParentRecordable.new(title: "Kiln shots"))
    named = Recording.new(recordable: ParentRecordable.new(name: "Untitled kiln"))
    typed = Recording.new(recordable_type: "Gallery")

    assert_equal "Kiln shots", RecordingStudioAttachable::Placements.place_label(titled)
    assert_equal "Untitled kiln", RecordingStudioAttachable::Placements.place_label(named)
    assert_equal "Gallery", RecordingStudioAttachable::Placements.place_label(typed)
  end

  def test_picker_libraries_use_the_host_list
    parent = Recording.new(id: "gallery-1", recordable_type: "Gallery")
    allowed = Recording.new(id: "lib-1", recordable_type: "RecordingStudioLibrary::Library")
    hidden = Recording.new(id: "lib-2", recordable_type: "RecordingStudioLibrary::Library")
    original = RecordingStudioAttachable.configuration.placement_picker_libraries
    RecordingStudioAttachable.configuration.placement_picker_libraries = ->(_parent) { [allowed] }

    RecordingStudioAttachable::Placements.stub(:live_library?, ->(library) { library.id == "lib-1" }) do
      assert_equal [allowed], RecordingStudioAttachable::Placements.picker_libraries_for(parent)
      refute_includes RecordingStudioAttachable::Placements.picker_libraries_for(parent), hidden
    end
  ensure
    RecordingStudioAttachable.configuration.placement_picker_libraries = original
  end

  def test_picker_libraries_are_empty_when_the_host_list_raises
    parent = Recording.new(id: "gallery-1", recordable_type: "Gallery")
    original = RecordingStudioAttachable.configuration.placement_picker_libraries
    RecordingStudioAttachable.configuration.placement_picker_libraries = ->(_parent) { raise "boom" }

    assert_empty RecordingStudioAttachable::Placements.picker_libraries_for(parent)
  ensure
    RecordingStudioAttachable.configuration.placement_picker_libraries = original
  end

  def test_usage_wraps_library_usages
    library_usage = RecordingStudioLibrary::Placements::Usage.new(
      placement_recording: :place,
      parent_recording: :gallery,
      label: "Kiln shots"
    )
    RecordingStudioLibrary.stub(:usages, [library_usage]) do
      usages = RecordingStudioAttachable::Placements.usage_for(:photo)

      assert_equal 1, usages.size
      assert_equal "Kiln shots", usages.first.label
      assert_equal :gallery, usages.first.parent_recording
    end
  end
end
