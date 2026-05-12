# frozen_string_literal: true

module RecordingStudioAttachable
  class Attachment < ApplicationRecord
    self.table_name = "recording_studio_attachable_attachments"

    attr_writer :validation_options

    has_one_attached :file

    validates :name, :attachment_kind, :original_filename, :content_type, :byte_size, presence: true
    validates :byte_size, numericality: { greater_than_or_equal_to: 0 }
    validate :content_type_must_be_allowed
    validate :attachment_kind_must_be_enabled

    scope :images, -> { where(attachment_kind: "image") }
    scope :files, -> { where(attachment_kind: "file") }

    class << self
      def build_from_blob(blob:, name: nil, description: nil, validation_options: {})
        content_type = blob.content_type.to_s
        new(
          name: name.presence || default_name_for(blob),
          description: description,
          attachment_kind: RecordingStudioAttachable.configuration.attachment_kind_for(content_type),
          original_filename: blob.filename.to_s,
          content_type: content_type,
          byte_size: blob.byte_size
        ).tap do |attachment|
          attachment.validation_options = validation_options
          attachment.file.attach(blob)
        end
      end

      private

      def default_name_for(blob)
        blob.filename.base.to_s.presence || blob.filename.to_s
      end
    end

    def image?
      attachment_kind == "image"
    end

    def previewable?
      return false unless file.attached? && image?

      file.variable? || file.blob.image?
    end

    def preview_target_named(name)
      return unless previewable?

      return variant_named(name) if file.variable?

      file
    end

    def variant_named(name)
      transformations = RecordingStudioAttachable.configuration.image_variant(name)
      raise ArgumentError, "Unknown image variant: #{name}" if transformations.blank?

      file.variant(transformations)
    end

    private

    def validation_options
      @validation_options ||= {}
    end

    def content_type_must_be_allowed
      return if content_type.blank?
      return if RecordingStudioAttachable.configuration.allowed_content_type?(
        content_type,
        allowed_content_types: validation_options[:allowed_content_types]
      )

      errors.add(:content_type, "is not allowed")
    end

    def attachment_kind_must_be_enabled
      return if attachment_kind.blank?
      return if RecordingStudioAttachable.configuration.attachment_kind_enabled?(
        attachment_kind,
        enabled_attachment_kinds: validation_options[:enabled_attachment_kinds]
      )

      errors.add(:attachment_kind, "is not enabled")
    end
  end
end
