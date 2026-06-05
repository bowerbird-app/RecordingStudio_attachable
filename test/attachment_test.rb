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

      assert_not attachment.previewable?
      assert_nil attachment.preview_target_named(:med)
    end

    def test_declares_attachment_as_non_root_recording_studio_recordable
      source = File.read(File.expand_path("../app/models/recording_studio_attachable/attachment.rb", __dir__))

      assert_includes source, "recording_studio_recordable("
      assert_includes source, 'label: "Attachment"'
      assert_includes source, 'plural_label: "Attachments"'
      assert_includes source, "root: false"
      assert_not_includes source, "allowed_parent_types:"
    end

    def test_attachment_declaration_metadata_when_recording_studio_apis_are_loaded
      unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:recordable_declaration_defined?)
        skip "RecordingStudio declaration APIs are unavailable"
      end

      restore_recording_studio_api!
      original_types = RecordingStudio.configuration.recordable_types
      RecordingStudio.configuration.recordable_types = ["RecordingStudioAttachable::Attachment"]

      assert RecordingStudio.recordable_declaration_defined?("RecordingStudioAttachable::Attachment")
      assert_not RecordingStudio.root_allowed?("RecordingStudioAttachable::Attachment")
      assert_equal [], RecordingStudio.declared_allowed_parent_types_for("RecordingStudioAttachable::Attachment")
    ensure
      RecordingStudio.configuration.recordable_types = original_types if defined?(original_types)
    end

    private

    def restore_recording_studio_api!
      singleton_class = RecordingStudio.singleton_class
      %i[configuration capability_options record! register_recordable_type register_capability].each do |method_name|
        singleton_class.send(:remove_method, method_name) if singleton_class.method_defined?(method_name)
      end
      load File.join(Gem.loaded_specs.fetch("recording_studio").full_gem_path, "lib/recording_studio.rb")
    end

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
