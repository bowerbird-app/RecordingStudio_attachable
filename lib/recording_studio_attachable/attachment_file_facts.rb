# frozen_string_literal: true

require "active_support/number_helper"

module RecordingStudioAttachable
  class AttachmentFileFacts
    TYPE_LABELS = {
      "image/jpeg" => "JPEG",
      "image/jpg" => "JPEG",
      "image/png" => "PNG",
      "image/gif" => "GIF",
      "image/webp" => "WEBP",
      "image/svg+xml" => "SVG",
      "image/avif" => "AVIF",
      "image/heic" => "HEIC",
      "image/heif" => "HEIC",
      "application/pdf" => "PDF"
    }.freeze

    def initialize(attachment)
      @attachment = attachment
    end

    def filename
      text(read(:original_filename))
    end

    def type_label
      type = mime_type
      return if type.blank?

      TYPE_LABELS[type] || subtype_label(type)
    end

    def dimensions_label
      width, height = pixel_size
      return if width.nil? || height.nil?

      "#{width} × #{height}"
    end

    def size_label
      bytes = byte_count
      return if bytes.nil? || bytes.negative?

      ActiveSupport::NumberHelper.number_to_human_size(bytes, strip_insignificant_zeros: true)
    end

    def labels
      [type_label, dimensions_label, size_label].compact
    end

    def any?
      filename.present? || labels.any?
    end

    private

    def mime_type
      raw = text(read(:content_type))
      return if raw.nil?

      raw.split(";").first.to_s.strip.downcase.presence
    end

    def subtype_label(type)
      type.split("/", 2).last.to_s.split("+", 2).first.to_s.upcase.presence
    end

    def pixel_size
      metadata = blob_metadata
      return [nil, nil] unless metadata.is_a?(Hash)

      [dimension(metadata, "width"), dimension(metadata, "height")]
    end

    def dimension(metadata, key)
      positive_integer(metadata[key] || metadata[key.to_sym])
    end

    def positive_integer(value)
      number = integer_value(value)
      number if number&.positive?
    end

    def integer_value(value)
      case value
      when Integer then value
      when Numeric then value.to_i
      when String then Integer(value, exception: false)
      end
    end

    def byte_count
      value = read(:byte_size)
      return if value.nil?

      integer_value(value)
    end

    def blob_metadata
      file = attached_file
      return unless file.respond_to?(:blob)

      blob = file.blob
      blob.metadata if blob.respond_to?(:metadata)
    end

    def attached_file
      file = read(:file)
      file if file.respond_to?(:attached?) && file.attached?
    end

    def read(method_name)
      return unless @attachment.respond_to?(method_name)

      @attachment.public_send(method_name)
    end

    def text(value)
      value.to_s.strip.presence
    end
  end
end
