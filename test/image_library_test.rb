# frozen_string_literal: true

require "test_helper"

class ImageLibraryTest < Minitest::Test
  def test_library_for_delegates_to_recording_studio_library
    captured = nil
    RecordingStudioLibrary.stub(:library_for, lambda { |parent, **kwargs|
      captured = [parent, kwargs]
      :library
    }) do
      result = RecordingStudioAttachable.library_for(:root, key: :campaign, actor: :ada)
      assert_equal :library, result
      assert_equal [:root, { key: :campaign, actor: :ada }], captured
    end
  end

  def test_find_library_and_lists_delegate
    RecordingStudioLibrary.stub(:find_library, :found) do
      assert_equal :found, RecordingStudioAttachable.find_library(:root, key: :default)
    end
    RecordingStudioLibrary.stub(:libraries_for, %i[one two]) do
      assert_equal %i[one two], RecordingStudioAttachable.libraries_for(:root)
    end
    RecordingStudioLibrary.stub(:libraries_in_root, [:live]) do
      assert_equal [:live], RecordingStudioAttachable.libraries_in_root(:root)
    end
  end

  def test_library_for_passes_key_and_parent_through
    captured = nil
    RecordingStudioLibrary.stub(:library_for, lambda { |parent, **kwargs|
      captured = [parent, kwargs]
      raise ArgumentError, "A parent is required" if parent.blank?
      raise ArgumentError, "Use a simple library key" if kwargs[:key].to_s.match?(/[A-Z ]/)

      :library
    }) do
      error = assert_raises(ArgumentError) { RecordingStudioAttachable.library_for(nil) }
      assert_match(/parent is required/, error.message)

      error = assert_raises(ArgumentError) { RecordingStudioAttachable.library_for(:root, key: "Campaign Stills") }
      assert_match(/simple library key/, error.message)
      assert_equal [:root, { key: "Campaign Stills", actor: nil }], captured
    end
  end

  def test_image_library_to_includes_library_and_the_alias
    calls = []
    RecordingStudio::Capabilities.stub(:include_for, lambda { |name, **options|
      calls << [name, options]
      Module.new
    }) do
      RecordingStudio::Capabilities::ImageLibrary.to(
        types: ["RecordingStudioAttachable::Attachment"],
        keys: [:default],
        foo: :bar
      )
    end

    assert_includes calls, [:library, { types: ["RecordingStudioAttachable::Attachment"], keys: [:default] }]
    assert_includes calls, [:image_library, { foo: :bar }]
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

  def test_library_label_syncs_to_library_configuration
    original = RecordingStudioAttachable.configuration.library_label
    RecordingStudioAttachable.configuration.library_label = ->(key) { key.to_s == "campaign" ? "Ads" : "Images" }
    RecordingStudioAttachable.configuration.sync_library_configuration!

    assert_equal "Ads", RecordingStudioLibrary.configuration.library_label.call("campaign")
    assert_equal "Images", RecordingStudioLibrary.configuration.library_label.call("default")
  ensure
    RecordingStudioAttachable.configuration.library_label = original
  end

  def test_public_api_does_not_create_rename_or_trash
    refute_respond_to RecordingStudioAttachable, :create_library
    refute_respond_to RecordingStudioAttachable, :rename_library
    refute_respond_to RecordingStudioAttachable, :trash_library
    refute_respond_to RecordingStudioAttachable, :default_library
  end
end
