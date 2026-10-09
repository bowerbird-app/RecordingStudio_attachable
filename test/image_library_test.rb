# frozen_string_literal: true

require "test_helper"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/library_query"
require_relative "../app/services/recording_studio_attachable/services/find_or_create_library"

class ImageLibraryTest < Minitest::Test
  Root = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)
  LibraryRecordable = Struct.new(:key, keyword_init: true)
  LibraryRecording = Struct.new(:id, :recordable_type, :parent_recording_id, :root_recording_id, :trashed_at, :recordable,
                                keyword_init: true) do
    attr_accessor :restored_with, :trashed_with

    def recording_studio_trashable_restore!(actor:)
      self.trashed_at = nil
      self.restored_with = actor
    end
  end

  Event = Struct.new(:recording, keyword_init: true)

  def setup
    @original_studio = defined?(RecordingStudio) ? RecordingStudio : nil
    stub_library_class!
    stub_studio!
  end

  def teardown
    restore_studio!
  end

  def test_library_for_returns_an_existing_default_library
    root = Root.new(id: "root-1", recordable_type: "Workspace")
    existing = LibraryRecording.new(
      id: "lib-1",
      recordable_type: "RecordingStudioAttachable::Library",
      parent_recording_id: "root-1",
      root_recording_id: "root-1",
      trashed_at: nil,
      recordable: LibraryRecordable.new(key: "default")
    )
    recording_class.stub(:where, [existing]) do
      result = RecordingStudioAttachable.library_for(root, actor: :ada)

      assert_equal existing, result
    end
  end

  def test_library_for_works_for_a_non_root_parent
    root = Root.new(id: "root-1", recordable_type: "Workspace")
    brand = Root.new(id: "brand-1", recordable_type: "Brand", root_recording: root)
    existing = LibraryRecording.new(
      id: "lib-brand",
      recordable_type: "RecordingStudioAttachable::Library",
      parent_recording_id: "brand-1",
      root_recording_id: "root-1",
      recordable: LibraryRecordable.new(key: "default")
    )
    recording_class.stub(:where, [existing]) do
      assert_equal existing, RecordingStudioAttachable.library_for(brand, actor: :ada)
    end
  end

  def test_library_for_restores_a_trashed_keyed_library
    root = Root.new(id: "root-1", recordable_type: "Workspace")
    trashed = LibraryRecording.new(
      id: "lib-1",
      recordable_type: "RecordingStudioAttachable::Library",
      parent_recording_id: "root-1",
      root_recording_id: "root-1",
      trashed_at: Time.now,
      recordable: LibraryRecordable.new(key: "campaign")
    )
    recording_class.stub(:where, [trashed]) do
      result = RecordingStudioAttachable.library_for(root, key: :campaign, actor: :ada)

      assert_equal trashed, result
      assert_nil trashed.trashed_at
      assert_equal :ada, trashed.restored_with
    end
  end

  def test_library_for_creates_with_an_idempotency_key
    root = Root.new(id: "root-1", recordable_type: "Workspace")
    created = LibraryRecording.new(id: "lib-2", recordable_type: "RecordingStudioAttachable::Library")
    captured = nil
    recording_class.stub(:where, []) do
      RecordingStudio.stub(:record!, lambda { |**kwargs|
        captured = kwargs
        Event.new(recording: created)
      }) do
        result = RecordingStudioAttachable.library_for(root, actor: :ada)

        assert_equal created, result
        assert_equal "created", captured[:action]
        assert_instance_of RecordingStudioAttachable::Library, captured[:recordable]
        assert_equal "default", captured[:recordable].key
        assert_equal root, captured[:root_recording]
        assert_equal root, captured[:parent_recording]
        assert_equal :ada, captured[:actor]
        assert_equal "recording-studio-attachable-library:default:root-1", captured[:idempotency_key]
      end
    end
  end

  def test_library_for_creates_a_keyed_library
    root = Root.new(id: "root-1", recordable_type: "Workspace")
    created = LibraryRecording.new(id: "lib-3", recordable_type: "RecordingStudioAttachable::Library")
    captured = nil
    recording_class.stub(:where, []) do
      RecordingStudio.stub(:record!, lambda { |**kwargs|
        captured = kwargs
        Event.new(recording: created)
      }) do
        result = RecordingStudioAttachable.library_for(root, key: :campaign, actor: :ada)

        assert_equal created, result
        assert_equal "campaign", captured[:recordable].key
        assert_equal "recording-studio-attachable-library:campaign:root-1", captured[:idempotency_key]
      end
    end
  end

  def test_library_for_rejects_a_messy_key
    root = Root.new(id: "root-1", recordable_type: "Workspace")

    error = assert_raises(ArgumentError) { RecordingStudioAttachable.library_for(root, key: "Campaign Stills") }

    assert_match(/simple library key/, error.message)
  end

  def test_library_for_requires_a_parent
    error = assert_raises(ArgumentError) { RecordingStudioAttachable.library_for(nil) }

    assert_equal "A parent is required", error.message
  end

  def test_libraries_for_lists_live_libraries_for_a_parent
    root = Root.new(id: "root-1", recordable_type: "Workspace")
    default = LibraryRecording.new(
      id: "lib-1",
      recordable_type: "RecordingStudioAttachable::Library",
      parent_recording_id: "root-1",
      recordable: LibraryRecordable.new(key: "default")
    )
    campaign = LibraryRecording.new(
      id: "lib-2",
      recordable_type: "RecordingStudioAttachable::Library",
      parent_recording_id: "root-1",
      recordable: LibraryRecordable.new(key: "campaign")
    )
    trashed = LibraryRecording.new(
      id: "lib-3",
      recordable_type: "RecordingStudioAttachable::Library",
      parent_recording_id: "root-1",
      trashed_at: Time.now,
      recordable: LibraryRecordable.new(key: "old")
    )

    recording_class.stub(:where, [default, campaign, trashed]) do
      assert_equal [default, campaign], RecordingStudioAttachable.libraries_for(root)
    end
  end

  def test_image_library_capability_module_delegates_to_include_for
    captured = nil
    RecordingStudio::Capabilities.stub(:include_for, lambda { |name, **options|
      captured = [name, options]
      Module.new
    }) do
      RecordingStudio::Capabilities::ImageLibrary.to(foo: :bar)
    end

    assert_equal [:image_library, { foo: :bar }], captured
  end

  def test_image_library_recording_methods_delegate
    recording = Object.new
    recording.define_singleton_method(:recordable_type) { "Workspace" }
    recording.extend(RecordingStudio::Capabilities::ImageLibrary::RecordingMethods)
    recording.define_singleton_method(:assert_capability!) { |*| true }
    captured = nil

    RecordingStudioAttachable.stub(:library_for, lambda { |parent, **kwargs|
      captured = [parent, kwargs]
      :library
    }) do
      assert_equal :library, recording.image_library(key: :campaign, actor: :ada)
      assert_equal [recording, { key: :campaign, actor: :ada }], captured
    end
    RecordingStudioAttachable.stub(:libraries_for, %i[one two]) do
      assert_equal %i[one two], recording.image_libraries
    end
    refute_respond_to recording, :create_image_library
    refute_respond_to recording, :rename_image_library
    refute_respond_to recording, :trash_image_library
    refute_respond_to recording, :default_library
  end

  def test_library_label_uses_host_config
    original = RecordingStudioAttachable.configuration.library_label
    RecordingStudioAttachable.configuration.library_label = ->(key) { key == "campaign" ? "Ads" : "Images" }

    assert_equal "Ads", RecordingStudioAttachable::Services::LibraryQuery.label_for_key(:campaign)
    assert_equal "Images", RecordingStudioAttachable::Services::LibraryQuery.label_for_key(:default)
  ensure
    RecordingStudioAttachable.configuration.library_label = original
  end

  def test_image_library_parent_walks_up_to_an_enabled_parent
    root = Root.new(id: "root-1", recordable_type: "Workspace")
    gallery = Root.new(id: "gallery-1", recordable_type: "Gallery", root_recording: root)
    gallery.define_singleton_method(:parent_recording) { root }

    RecordingStudioAttachable::Authorization.stub(:library_enabled?, lambda { |recording:|
      recording.recordable_type == "Workspace"
    }) do
      assert_equal root, RecordingStudioAttachable::Services::LibraryQuery.image_library_parent_for(gallery)
    end
  end

  def test_libraries_in_root_and_title
    root = Root.new(id: "root-1", recordable_type: "Workspace")
    library = LibraryRecording.new(
      id: "lib-1",
      recordable_type: "RecordingStudioAttachable::Library",
      root_recording_id: "root-1",
      recordable: LibraryRecordable.new(key: "campaign")
    )
    recording_class.stub(:where, [library]) do
      assert_equal [library], RecordingStudioAttachable.libraries_in_root(root)
      assert_equal "Campaign", RecordingStudioAttachable::Placements.library_title(library)
    end
  end

  def test_public_api_does_not_create_rename_or_trash
    refute_respond_to RecordingStudioAttachable, :create_library
    refute_respond_to RecordingStudioAttachable, :rename_library
    refute_respond_to RecordingStudioAttachable, :trash_library
    refute_respond_to RecordingStudioAttachable, :default_library
  end

  private

  def stub_library_class!
    return if defined?(RecordingStudioAttachable::Library)

    RecordingStudioAttachable.const_set(
      :Library,
      Class.new do
        attr_accessor :key

        def initialize(key: nil)
          @key = key
        end
      end
    )
    @created_library_stub = true
  end

  def stub_studio!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.const_set(:Recording, Class.new) unless studio.const_defined?(:Recording)
    studio.define_singleton_method(:record!) { |**| raise "record! is not stubbed" } unless studio.respond_to?(:record!)
    recording_class
  end

  def recording_class
    klass = RecordingStudio::Recording
    klass.define_singleton_method(:where) { |*| [] } unless klass.respond_to?(:where)

    klass
  end

  def restore_studio!
    return unless @created_library_stub && RecordingStudioAttachable.const_defined?(:Library)

    RecordingStudioAttachable.send(:remove_const, :Library)
  end
end
