# frozen_string_literal: true

require "test_helper"

class LibraryAttachmentTest < Minitest::Test
  FakeFilename = Struct.new(:value) do
    def to_s
      value
    end

    def base
      File.basename(value, ".*")
    end
  end
  FakeBlob = Struct.new(:content_type, :filename, :byte_size, keyword_init: true)
  FakeRoot = Struct.new(:id)

  def test_attrs_for_builds_an_attachment_payload
    blob = FakeBlob.new(content_type: "image/jpeg", filename: FakeFilename.new("kiln-hero.jpg"), byte_size: 1200)
    root = FakeRoot.new("root-1")

    attrs = RecordingStudioAttachable::LibraryAttachment.attrs_for(
      blob: blob,
      name: "Kiln hero",
      caption: "Warm glaze",
      credit: "Ada",
      alt_text: "A kiln",
      root_recording: root,
      validation_options: { max_file_size: 1 }
    )

    assert_equal "Kiln hero", attrs[:name]
    assert_equal "Warm glaze", attrs[:caption]
    assert_equal "Ada", attrs[:credit]
    assert_equal "A kiln", attrs[:alt_text]
    assert_equal "image", attrs[:attachment_kind]
    assert_equal "kiln-hero.jpg", attrs[:original_filename]
    assert_equal "image/jpeg", attrs[:content_type]
    assert_equal 1200, attrs[:byte_size]
    assert_equal blob, attrs[:file]
    assert_equal "root-1", attrs[:root_recording_id]
    assert_equal({ max_file_size: 1 }, attrs[:validation_options])
  end

  def test_library_recording_predicate
    library = Struct.new(:recordable_type).new("RecordingStudioLibrary::Library")
    photo = Struct.new(:recordable_type).new("RecordingStudioAttachable::Attachment")

    assert RecordingStudioAttachable::LibraryAttachment.library_recording?(library)
    refute RecordingStudioAttachable::LibraryAttachment.library_recording?(photo)
  end
end
