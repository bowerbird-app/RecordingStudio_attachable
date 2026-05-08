# frozen_string_literal: true

require "test_helper"

unless defined?(ApplicationRecord)
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end

unless ApplicationRecord.respond_to?(:has_one_attached)
  ApplicationRecord.define_singleton_method(:has_one_attached) do |*_args|
  end
end

require_relative "../app/models/recording_studio_attachable/attachment"

module RecordingStudioAttachable
  class AttachmentTest < Minitest::Test
    def test_previewable_for_variable_images_and_uses_variant_target
      attachment = build_attachment_double(image: true)
      file = build_file_double(attached: true, variable: true, image: true)
      variant = Object.new
      attachment.define_singleton_method(:file) { file }

      attachment.stub(:variant_named, variant) do
        assert attachment.previewable?
        assert_same variant, attachment.preview_target_named(:med)
      end
    end

    def test_previewable_for_non_variable_images_and_uses_original_blob_target
      attachment = build_attachment_double(image: true)
      file = build_file_double(attached: true, variable: false, image: true)
      attachment.define_singleton_method(:file) { file }

      assert attachment.previewable?
      assert_same file, attachment.preview_target_named(:med)
    end

    def test_preview_target_is_nil_for_non_image_attachments
      attachment = build_attachment_double(image: false)
      file = build_file_double(attached: true, variable: false, image: false)
      attachment.define_singleton_method(:file) { file }

      refute attachment.previewable?
      assert_nil attachment.preview_target_named(:med)
    end

    private

    def build_attachment_double(image:)
      Attachment.allocate.tap do |attachment|
        attachment.define_singleton_method(:image?) { image }
      end
    end

    def build_file_double(attached:, variable:, image:)
      blob = Struct.new(:image?).new(image)

      Object.new.tap do |file|
        file.define_singleton_method(:attached?) { attached }
        file.define_singleton_method(:variable?) { variable }
        file.define_singleton_method(:blob) { blob }
      end
    end
  end
end
