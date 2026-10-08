# frozen_string_literal: true

require "test_helper"

class AttachmentFileFactsTest < Minitest::Test
  def test_labels_use_the_known_type_pixel_size_and_file_size
    facts = facts_for(
      original_filename: "kiln-canister-hero.jpg",
      content_type: "image/jpeg",
      byte_size: 204_800,
      file: sized_file("width" => 1280, "height" => 720)
    )

    assert_equal "kiln-canister-hero.jpg", facts.filename
    assert_equal "JPEG", facts.type_label
    assert_equal "1280 × 720", facts.dimensions_label
    assert_equal "200 KB", facts.size_label
    assert_equal ["JPEG", "1280 × 720", "200 KB"], facts.labels
    assert facts.any?
  end

  def test_known_types_and_a_plain_subtype
    {
      "image/jpeg" => "JPEG",
      "image/jpg" => "JPEG",
      "image/png" => "PNG",
      "image/gif" => "GIF",
      "image/webp" => "WEBP",
      "image/svg+xml" => "SVG",
      "image/avif" => "AVIF",
      "image/heic" => "HEIC",
      "image/heif" => "HEIC",
      "application/pdf" => "PDF",
      "image/tiff" => "TIFF",
      "IMAGE/JPEG; charset=binary" => "JPEG"
    }.each do |content_type, label|
      assert_equal label, facts_for(content_type: content_type).type_label, content_type
    end
  end

  def test_symbol_metadata_and_numeric_strings
    facts = facts_for(
      content_type: "image/png",
      byte_size: "1536",
      file: sized_file(width: 800, height: "600")
    )

    assert_equal ["PNG", "800 × 600", "1.5 KB"], facts.labels
  end

  def test_float_pixel_size_truncates_to_whole_pixels
    facts = facts_for(file: sized_file("width" => 1280.0, "height" => 720.4))

    assert_equal "1280 × 720", facts.dimensions_label
  end

  def test_omits_blank_or_unusable_facts
    empty = RecordingStudioAttachable::AttachmentFileFacts.new(Object.new)
    refute empty.any?
    assert_nil empty.filename
    assert_empty empty.labels

    blank = facts_for(original_filename: "  ", content_type: "", byte_size: nil, file: unattached_file)
    refute blank.any?

    zero_edge = facts_for(byte_size: 0, file: sized_file("width" => 0, "height" => 10))
    assert_equal ["0 Bytes"], zero_edge.labels

    missing_edge = facts_for(byte_size: -1, file: sized_file("width" => 10, "height" => nil))
    assert_empty missing_edge.labels

    assert_nil facts_for(file: sized_file("nope")).dimensions_label
  end

  private

  Snapshot = Struct.new(:original_filename, :content_type, :byte_size, :file, keyword_init: true)

  def facts_for(**attributes)
    RecordingStudioAttachable::AttachmentFileFacts.new(Snapshot.new(**attributes))
  end

  def sized_file(metadata)
    blob = Object.new
    blob.define_singleton_method(:metadata) { metadata }
    file = Object.new
    file.define_singleton_method(:attached?) { true }
    file.define_singleton_method(:blob) { blob }
    file
  end

  def unattached_file
    file = Object.new
    file.define_singleton_method(:attached?) { false }
    file
  end
end
