# frozen_string_literal: true

require "test_helper"
require "active_job"
require_relative "support/coverage_database"
require_relative "../app/jobs/recording_studio_attachable/preprocess_variants_job"

unless defined?(ApplicationRecord)
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end

require "active_storage/attached/model"
require "active_storage/reflection"
unless ActiveRecord::Reflection.singleton_class.ancestors.include?(ActiveStorage::Reflection::ReflectionExtension)
  ActiveRecord::Reflection.singleton_class.prepend(ActiveStorage::Reflection::ReflectionExtension)
end
ActiveRecord::Base.include(ActiveStorage::Reflection::ActiveRecordExtensions) unless ActiveRecord::Base.respond_to?(:attachment_reflections)
ApplicationRecord.include(ActiveStorage::Attached::Model) unless ApplicationRecord.respond_to?(:has_one_attached)

require_relative "../app/models/recording_studio_attachable/attachment"

class AttachmentPersistenceTest < Minitest::Test
  extend CoverageDatabase

  capture_real_models!
  include CoverageDatabase

  def setup
    @created_attachment_ids = []
    @created_blob_ids = []
    connect_coverage_database!
    @previous_configuration = RecordingStudioAttachable.configuration
    @configuration = RecordingStudioAttachable::Configuration.new
    RecordingStudioAttachable.instance_variable_set(:@configuration, @configuration)
    @previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  def teardown
    if defined?(ActiveStorage::Attachment) && @created_attachment_ids&.any?
      ActiveStorage::Attachment.where(record_id: @created_attachment_ids).delete_all
    end
    if defined?(RecordingStudioAttachable::Attachment) && @created_attachment_ids&.any?
      RecordingStudioAttachable::Attachment.where(id: @created_attachment_ids).delete_all
    end
    ActiveStorage::Blob.where(id: @created_blob_ids).delete_all if defined?(ActiveStorage::Blob) && @created_blob_ids&.any?
    ActiveJob::Base.queue_adapter = @previous_adapter if @previous_adapter
    RecordingStudioAttachable.instance_variable_set(:@configuration, @previous_configuration)
    restore_active_storage!
  end

  def test_an_unknown_variant_name_is_rejected
    attachment = RecordingStudioAttachable::Attachment.new(name: "Poster", attachment_kind: "image")
    error = assert_raises(ArgumentError) { attachment.variant_named(:nope) }
    assert_match(/Unknown image variant/, error.message)
  end

  def test_build_from_blob_stores_the_file_name_root_and_image_kind
    with_disk_service do
      blob = create_blob("photo.png", "image/png", UploadBlobBytes::PNG)
      root = Struct.new(:id).new(SecureRandom.uuid)

      attachment = RecordingStudioAttachable::Attachment.build_from_blob(
        blob: blob,
        description: "Window",
        caption: "North light",
        credit: "Studio",
        alt_text: "A window",
        root_recording: root,
        validation_options: { allowed_content_types: ["image/*"], enabled_attachment_kinds: [:image] }
      )
      assert attachment.save, attachment.errors.full_messages.to_sentence
      remember(attachment)

      assert attachment.image?
      assert_equal "photo", attachment.name
      assert_equal "photo.png", attachment.original_filename
      assert_equal "image/png", attachment.content_type
      assert_equal UploadBlobBytes::PNG.bytesize, attachment.byte_size
      assert_equal root.id, attachment.root_recording_id
      assert_equal "North light", attachment.caption
      assert attachment.previewable?
      assert_equal attachment.file, attachment.preview_target_named(:med)
      assert_includes RecordingStudioAttachable::Attachment.images, attachment
      refute_includes RecordingStudioAttachable::Attachment.files, attachment
    end
  end

  def test_an_explicit_name_is_kept_and_a_root_without_an_id_is_ignored
    with_disk_service do
      blob = create_blob("notes.txt", "text/plain", "notes")
      attachment = RecordingStudioAttachable::Attachment.build_from_blob(
        blob: blob,
        name: "Field notes",
        root_recording: Object.new,
        validation_options: {
          allowed_content_types: ["text/plain"],
          enabled_attachment_kinds: [:file]
        }
      )

      assert attachment.valid?, attachment.errors.full_messages.to_sentence
      assert_equal "Field notes", attachment.name
      assert_nil attachment.root_recording_id
      refute attachment.image?
    end
  end

  def test_svg_is_rejected_for_image_star_and_accepted_when_the_type_is_named
    with_disk_service do
      blob = create_blob("icon.svg", "image/svg+xml", "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>")
      rejected = RecordingStudioAttachable::Attachment.build_from_blob(
        blob: blob,
        validation_options: { allowed_content_types: ["image/*"], enabled_attachment_kinds: [:image] }
      )

      refute rejected.valid?
      assert_includes rejected.errors[:content_type], "is not allowed"

      allowed = RecordingStudioAttachable::Attachment.build_from_blob(
        blob: blob,
        validation_options: {
          allowed_content_types: ["image/svg+xml"],
          enabled_attachment_kinds: [:image]
        }
      )

      assert allowed.valid?, allowed.errors.full_messages.to_sentence
    end
  end

  def test_a_disabled_kind_and_a_negative_size_are_rejected
    with_disk_service do
      blob = create_blob("notes.txt", "text/plain", "notes")
      attachment = RecordingStudioAttachable::Attachment.build_from_blob(
        blob: blob,
        validation_options: {
          allowed_content_types: ["text/plain"],
          enabled_attachment_kinds: [:image]
        }
      )

      refute attachment.valid?
      assert_includes attachment.errors[:attachment_kind], "is not enabled"

      attachment.byte_size = -1
      refute attachment.valid?
      assert attachment.errors[:byte_size].any?
    end
  end

  def test_blank_type_and_kind_skip_the_allow_list_and_still_fail_presence
    attachment = RecordingStudioAttachable::Attachment.new(name: "Untitled")

    refute attachment.valid?
    assert_includes attachment.errors[:content_type], "can't be blank"
    assert_includes attachment.errors[:attachment_kind], "can't be blank"
    refute_includes attachment.errors[:content_type], "is not allowed"
    refute_includes attachment.errors[:attachment_kind], "is not enabled"
  end

  def test_rails_and_direct_urls_follow_the_requested_mode
    with_disk_service do
      blob = create_blob("photo.png", "image/png", UploadBlobBytes::PNG)
      attachment = RecordingStudioAttachable::Attachment.build_from_blob(blob: blob, name: "Photo")
      assert attachment.save, attachment.errors.full_messages.to_sentence
      remember(attachment)
      @configuration.direct_url_host = "images.example.test"

      assert_equal "/files/photo", attachment.original_url(mode: :rails, rails_url: "/files/photo")
      assert_equal "https://images.example.test/#{blob.key}", attachment.original_url(mode: :direct, rails_url: "/files/photo")
      assert_equal "/previews/med", attachment.url_for_variant(:med, mode: :rails, rails_url: "/previews/med")
      refute attachment.variant_processed?(:med)

      bare = RecordingStudioAttachable::Attachment.new(
        name: "Bare",
        attachment_kind: "image",
        original_filename: "bare.png",
        content_type: "image/png",
        byte_size: 1
      )
      assert_equal "/files/bare", bare.original_url(mode: :direct, rails_url: "/files/bare")
      assert_equal "/previews/bare", bare.url_for_variant(:med, mode: :direct, rails_url: "/previews/bare")
      error = assert_raises(ArgumentError) { bare.url_for_variant(:med, mode: :direct) }
      assert_match(/rails_url is required/, error.message)
    end
  end

  def test_a_non_image_direct_variant_url_stays_on_the_rails_path
    with_disk_service do
      blob = create_blob("brief.pdf", "application/pdf", "%PDF-1.4\n")
      attachment = RecordingStudioAttachable::Attachment.build_from_blob(
        blob: blob,
        validation_options: {
          allowed_content_types: ["application/pdf"],
          enabled_attachment_kinds: [:file]
        }
      )
      assert attachment.save, attachment.errors.full_messages.to_sentence
      remember(attachment)
      @configuration.url_mode = :direct
      @configuration.direct_url_host = "images.example.test"

      assert_equal "/previews/brief", attachment.url_for_variant(:med, rails_url: "/previews/brief")
      assert_nil attachment.url_for_variant(:med, mode: :direct)
    end
  end

  def test_a_processed_variant_uses_the_variant_blob_key
    @configuration.direct_url_host = "images.example.test"
    attachment = RecordingStudioAttachable::Attachment.new(
      name: "Poster",
      attachment_kind: "image",
      original_filename: "poster.png",
      content_type: "image/png",
      byte_size: 12
    )
    stand_in = variant_file("original-key", "variant-key")
    attachment.define_singleton_method(:file) { stand_in }

    assert_equal(
      "https://images.example.test/variant-key",
      attachment.url_for_variant(:med, mode: :direct, rails_url: "/previews/med")
    )
    assert attachment.variant_processed?(:med)
  end

  def test_a_variant_without_a_key_keeps_the_rails_preview
    @configuration.direct_url_host = "images.example.test"
    attachment = RecordingStudioAttachable::Attachment.new(
      name: "Poster",
      attachment_kind: "image",
      original_filename: "poster.png",
      content_type: "image/png",
      byte_size: 12
    )
    attachment.define_singleton_method(:id) { "att-keyless" }
    stand_in = variant_file("original-key", nil)
    attachment.define_singleton_method(:file) { stand_in }

    assert_equal "/previews/med", attachment.url_for_variant(:med, mode: :direct, rails_url: "/previews/med")
    refute attachment.variant_processed?(:med)
  end

  private

  def create_blob(filename, content_type, bytes)
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: filename,
      byte_size: bytes.bytesize,
      checksum: checksum_for(bytes),
      content_type: content_type
    )
    blob.upload(StringIO.new(bytes)) unless bytes.empty?
    @created_blob_ids << blob.id
    blob
  end

  def remember(attachment)
    @created_attachment_ids << attachment.id
    @created_blob_ids << attachment.file.blob.id if attachment.file.attached?
  end

  def variant_file(original_key, variant_key)
    original = Object.new
    original.define_singleton_method(:key) { original_key }
    original.define_singleton_method(:image?) { true }

    image = Object.new
    image.define_singleton_method(:key) { nil }
    variant_blob = Object.new
    variant_blob.define_singleton_method(:key) { variant_key }
    image.define_singleton_method(:blob) { variant_blob }

    variant = Object.new
    variant.define_singleton_method(:image) { image }

    file = Object.new
    file.define_singleton_method(:attached?) { true }
    file.define_singleton_method(:variable?) { true }
    file.define_singleton_method(:blob) { original }
    file.define_singleton_method(:variant) { |_transformations| variant }
    file
  end
end
