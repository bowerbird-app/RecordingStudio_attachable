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

require "active_job"
require_relative "../app/models/recording_studio_attachable/attachment"
require_relative "../app/jobs/recording_studio_attachable/preprocess_variants_job"

module RecordingStudioAttachable
  class AttachmentUrlTest < Minitest::Test
    def setup
      @configuration = RecordingStudioAttachable.configuration
      @previous = {
        url_mode: @configuration.url_mode,
        direct_url_host: @configuration.direct_url_host,
        preprocessed_variants: @configuration.preprocessed_variants
      }
      @configuration.url_mode = :rails
      @configuration.direct_url_host = nil
      @configuration.preprocessed_variants = %i[small med large]
    end

    def teardown
      @configuration.url_mode = @previous[:url_mode]
      @configuration.direct_url_host = @previous[:direct_url_host]
      @configuration.preprocessed_variants = @previous[:preprocessed_variants]
    end

    def test_url_for_variant_defaults_to_rails_mode
      attachment = build_variable_image_attachment(original_key: "original-key", variant_key: "variant-key")

      assert_equal(
        "/attachments/1/preview/med",
        attachment.url_for_variant(:med, rails_url: "/attachments/1/preview/med")
      )
    end

    def test_url_for_variant_per_call_override_to_direct
      @configuration.direct_url_host = "images.featuredin.press"
      attachment = build_variable_image_attachment(original_key: "original-key", variant_key: "variant-key")

      assert_equal(
        "https://images.featuredin.press/variant-key",
        attachment.url_for_variant(:med, mode: :direct, rails_url: "/attachments/1/preview/med")
      )
    end

    def test_url_for_variant_direct_uses_variant_blob_key_not_original
      @configuration.url_mode = :direct
      @configuration.direct_url_host = "images.featuredin.press"
      attachment = build_variable_image_attachment(original_key: "original-key", variant_key: "variant-key")

      url = attachment.url_for_variant(:med, rails_url: "/attachments/1/preview/med")

      assert_equal "https://images.featuredin.press/variant-key", url
      assert_no_match(/original-key/, url)
    end

    def test_original_url_direct_uses_original_blob_key
      @configuration.direct_url_host = "images.featuredin.press"
      attachment = build_variable_image_attachment(original_key: "original-key", variant_key: "variant-key")

      assert_equal(
        "https://images.featuredin.press/original-key",
        attachment.original_url(mode: :direct, rails_url: "/attachments/1/file")
      )
    end

    def test_direct_mode_raises_when_host_is_missing
      @configuration.url_mode = :direct
      @configuration.direct_url_host = nil
      attachment = build_variable_image_attachment(original_key: "original-key", variant_key: "variant-key")

      error = assert_raises(ConfigurationError) do
        attachment.url_for_variant(:med, rails_url: "/attachments/1/preview/med")
      end

      assert_match(/direct_url_host must be set/, error.message)
    end

    def test_direct_mode_falls_back_to_rails_url_and_enqueues_when_variant_unprocessed
      @configuration.url_mode = :direct
      @configuration.direct_url_host = "images.featuredin.press"
      attachment = build_variable_image_attachment(original_key: "original-key", variant_key: nil)
      attachment.define_singleton_method(:id) { "att-42" }
      enqueued = nil

      PreprocessVariantsJob.stub(:perform_later, lambda { |id|
        enqueued = id
      }) do
        url = attachment.url_for_variant(:med, rails_url: "/attachments/1/preview/med")

        assert_equal "/attachments/1/preview/med", url
        assert_equal "att-42", enqueued
      end
    end

    def test_direct_mode_never_returns_original_key_for_unprocessed_variant
      @configuration.url_mode = :direct
      @configuration.direct_url_host = "images.featuredin.press"
      attachment = build_variable_image_attachment(original_key: "original-key", variant_key: nil)
      attachment.define_singleton_method(:id) { "att-99" }

      PreprocessVariantsJob.stub(:perform_later, true) do
        url = attachment.url_for_variant(:large, rails_url: "/rails/preview/large")

        assert_equal "/rails/preview/large", url
        assert_no_match(/original-key/, url)
      end
    end

    def test_non_image_attachments_do_not_enqueue_preprocessing
      attachment = build_attachment(image: false, attached: true, variable: false, original_key: "pdf-key")
      called = false

      PreprocessVariantsJob.stub(:perform_later, lambda { |_|
        called = true
      }) do
        attachment.enqueue_variant_preprocessing
      end

      assert_not called
    end

    def test_non_variable_previewable_image_uses_original_direct_url_for_variant
      @configuration.direct_url_host = "images.featuredin.press"
      attachment = build_attachment(image: true, attached: true, variable: false, original_key: "gif-key")

      assert_equal(
        "https://images.featuredin.press/gif-key",
        attachment.url_for_variant(:med, mode: :direct, rails_url: "/preview/med")
      )
    end

    def test_rails_mode_requires_rails_url
      attachment = build_variable_image_attachment(original_key: "original-key", variant_key: "variant-key")

      error = assert_raises(ArgumentError) do
        attachment.url_for_variant(:med)
      end

      assert_match(/rails_url is required/, error.message)
    end

    def test_after_commit_hook_enqueues_preprocessing_for_variable_images
      model_source = File.read(File.expand_path("../app/models/recording_studio_attachable/attachment.rb", __dir__))
      urls_source = File.read(File.expand_path("../lib/recording_studio_attachable/attachment_urls.rb", __dir__))

      assert_includes model_source, "after_commit :enqueue_variant_preprocessing, on: :create"
      assert_includes model_source, "include AttachmentUrls"
      assert_includes urls_source, "PreprocessVariantsJob.perform_later(id)"
    end

    private

    def build_variable_image_attachment(original_key:, variant_key:)
      build_attachment(
        image: true,
        attached: true,
        variable: true,
        original_key: original_key,
        variant_key: variant_key
      )
    end

    def build_attachment(image:, attached:, variable:, original_key:, variant_key: nil)
      blob = Object.new
      blob.define_singleton_method(:key) { original_key }
      blob.define_singleton_method(:image?) { image }

      variant_image = nil
      if variant_key
        variant_image = Object.new
        variant_image.define_singleton_method(:key) { variant_key }
        variant_blob = Object.new
        variant_blob.define_singleton_method(:key) { variant_key }
        variant_image.define_singleton_method(:blob) { variant_blob }
      end

      variant = Object.new
      variant.define_singleton_method(:image) { variant_image }

      file = Object.new
      file.define_singleton_method(:attached?) { attached }
      file.define_singleton_method(:variable?) { variable }
      file.define_singleton_method(:blob) { blob }
      file.define_singleton_method(:variant) { |_transformations| variant }

      Attachment.allocate.tap do |attachment|
        attachment.define_singleton_method(:image?) { image }
        attachment.define_singleton_method(:file) { file }
      end
    end
  end
end
