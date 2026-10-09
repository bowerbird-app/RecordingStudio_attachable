# frozen_string_literal: true

require "test_helper"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/find_or_create_library"

class ImageLibraryTest < Minitest::Test
  Root = Struct.new(:id, :recordable_type, keyword_init: true)
  LibraryRecording = Struct.new(:id, :recordable_type, :parent_recording_id, :root_recording_id, :trashed_at, :recordable,
                                keyword_init: true) do
    attr_accessor :restored_with

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

  def test_library_for_returns_an_existing_live_library
    root = Root.new(id: "root-1", recordable_type: "Workspace")
    existing = LibraryRecording.new(
      id: "lib-1",
      recordable_type: "RecordingStudioAttachable::Library",
      parent_recording_id: "root-1",
      root_recording_id: "root-1",
      trashed_at: nil
    )
    recording_class.stub(:where, [existing]) do
      result = RecordingStudioAttachable.library_for(root, actor: :ada)

      assert_equal existing, result
    end
  end

  def test_library_for_restores_a_trashed_library
    root = Root.new(id: "root-1", recordable_type: "Workspace")
    trashed = LibraryRecording.new(
      id: "lib-1",
      recordable_type: "RecordingStudioAttachable::Library",
      parent_recording_id: "root-1",
      root_recording_id: "root-1",
      trashed_at: Time.now
    )
    recording_class.stub(:where, [trashed]) do
      result = RecordingStudioAttachable.library_for(root, actor: :ada)

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
        assert_equal root, captured[:root_recording]
        assert_equal root, captured[:parent_recording]
        assert_equal :ada, captured[:actor]
        assert_equal "recording-studio-attachable-library:root-1", captured[:idempotency_key]
      end
    end
  end

  def test_library_for_requires_a_workspace
    error = assert_raises(ArgumentError) { RecordingStudioAttachable.library_for(nil) }

    assert_equal "A workspace is required", error.message
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

  def test_image_library_recording_method_delegates_to_library_for
    recording = Object.new
    recording.define_singleton_method(:recordable_type) { "Workspace" }
    recording.extend(RecordingStudio::Capabilities::ImageLibrary::RecordingMethods)
    recording.define_singleton_method(:assert_capability!) { |*| true }

    RecordingStudioAttachable.stub(:library_for, :library) do
      assert_equal :library, recording.image_library(actor: :ada)
    end
  end

  private

  def stub_library_class!
    return if defined?(RecordingStudioAttachable::Library)

    RecordingStudioAttachable.const_set(:Library, Class.new)
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
