# frozen_string_literal: true

require "test_helper"

class LibraryPathOverridesTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, keyword_init: true)

  class Helper
    include RecordingStudioAttachable::LibraryPathOverrides

    def initialize(routes)
      @routes = routes
    end

    def recording_studio_attachable
      @routes
    end
  end

  def setup
    @routes = Object.new
    @routes.define_singleton_method(:attachment_path) { |item, **| "/attachments/#{item.id}" }
    @routes.define_singleton_method(:recording_attachment_upload_path) { |item, **| "/recordings/#{item.id}/upload" }
    @helper = Helper.new(@routes)
  end

  def test_library_item_path_opens_the_attachment_editor
    photo = FakeRecording.new(id: "photo-1", recordable_type: "RecordingStudioAttachable::Attachment")

    assert_equal "/attachments/photo-1", @helper.library_item_path_for(photo)
  end

  def test_library_item_path_falls_through_for_other_types
    sample = FakeRecording.new(id: "sample-1", recordable_type: "RecordingStudioLibrary::SampleItem")

    assert_nil @helper.library_item_path_for(sample)
  end

  def test_new_item_path_opens_the_attachment_upload
    library = FakeRecording.new(id: "lib-1", recordable_type: "RecordingStudioLibrary::Library")

    assert_equal "/recordings/lib-1/upload", @helper.library_new_item_path_for(library)
    assert_equal "/recordings/lib-1/upload", @helper.library_new_item_path_for(library, type: "RecordingStudioAttachable::Attachment")
  end

  def test_new_item_path_falls_through_for_other_types
    library = FakeRecording.new(id: "lib-1", recordable_type: "RecordingStudioLibrary::Library")

    assert_nil @helper.library_new_item_path_for(library, type: "RecordingStudioLibrary::SampleItem")
  end
end
