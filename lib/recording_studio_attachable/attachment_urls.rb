# frozen_string_literal: true

module RecordingStudioAttachable
  # Delivery URL helpers for Attachment originals and named variants.
  module AttachmentUrls
    # Public delivery URL for a named image variant.
    #
    # +mode:+ overrides +config.url_mode+ for this call (+:rails+ or +:direct+).
    # +rails_url:+ is the authorized engine preview path/URL. Required when the
    # resolved mode is +:rails+, and used as the fallback when +:direct+ would
    # otherwise return a URL for an unprocessed variant.
    def url_for_variant(variant_name, mode: nil, rails_url: nil)
      case resolve_url_mode(mode)
      when :rails
        rails_delivery_url(rails_url)
      when :direct
        direct_variant_url(variant_name, rails_url: rails_url)
      end
    end

    # Public delivery URL for the original uploaded file.
    #
    # +mode:+ overrides +config.url_mode+. +rails_url:+ is the authorized engine
    # file path/URL and is required when the resolved mode is +:rails+.
    def original_url(mode: nil, rails_url: nil)
      case resolve_url_mode(mode)
      when :rails
        rails_delivery_url(rails_url)
      when :direct
        DirectUrl.ensure_host_configured!
        return rails_delivery_url(rails_url) unless file.attached?

        DirectUrl.build(file.blob.key)
      end
    end

    def variant_processed?(variant_name)
      processed_variant_blob_key(variant_name).present?
    end

    def enqueue_variant_preprocessing
      return unless should_preprocess_variants?

      PreprocessVariantsJob.perform_later(id)
    end

    private

    def resolve_url_mode(mode)
      RecordingStudioAttachable.configuration.resolve_url_mode(mode)
    end

    def rails_delivery_url(rails_url)
      raise ArgumentError, "rails_url is required when url mode is :rails" if rails_url.blank?

      rails_url
    end

    def direct_variant_url(variant_name, rails_url:)
      DirectUrl.ensure_host_configured!
      return unprocessed_direct_variant_fallback(rails_url) unless file.attached?
      return non_variable_direct_variant_url(rails_url) unless file.variable?

      variant_key = processed_variant_blob_key(variant_name)
      return DirectUrl.build(variant_key) if variant_key.present?

      # Unprocessed: keep serving the authorized Rails preview (which can process
      # on demand) and enqueue preprocessing so the next direct request can use
      # the variant blob key. Never advertise the original's direct URL as a
      # resize — that would lie about dimensions and bytes.
      enqueue_variant_preprocessing
      rails_delivery_url(rails_url)
    end

    def unprocessed_direct_variant_fallback(rails_url)
      return rails_url if rails_url.present?

      raise ArgumentError, "rails_url is required when a direct variant URL cannot be built"
    end

    def non_variable_direct_variant_url(rails_url)
      return DirectUrl.build(file.blob.key) if previewable?
      return rails_delivery_url(rails_url) if rails_url.present?

      nil
    end

    def processed_variant_blob_key(variant_name)
      return unless file.attached? && file.variable?

      image = variant_named(variant_name).try(:image)
      key = variant_image_blob_key(image)
      return if key.blank? || key == file.blob.key

      key
    end

    def variant_image_blob_key(image)
      return if image.blank?
      return image.key if image.respond_to?(:key) && image.key.present?
      return image.blob.key if image.respond_to?(:blob) && image.blob&.key.present?

      nil
    end

    def should_preprocess_variants?
      return false unless file.attached?
      return false unless file.respond_to?(:variable?) && file.variable?
      return false if RecordingStudioAttachable.configuration.preprocessed_variants.blank?

      true
    end
  end
end
