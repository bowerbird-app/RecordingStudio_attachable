# frozen_string_literal: true

module RecordingStudioAttachable
  # Processes configured image variants after an attachment is committed.
  #
  # Idempotent: Active Storage's +processed+ skips work when the variant_record
  # (and its image blob) already exist. Safe for non-image and unvariable files
  # — those exit without transforming.
  class PreprocessVariantsJob < ActiveJob::Base
    queue_as :default

    def perform(attachment_id)
      attachment = Attachment.find_by(id: attachment_id)
      return unless preprocessable?(attachment)

      RecordingStudioAttachable.configuration.preprocessed_variants.each do |variant_name|
        transformations = RecordingStudioAttachable.configuration.image_variant(variant_name)
        next if transformations.blank?

        attachment.file.variant(transformations).processed
      end
    end

    private

    def preprocessable?(attachment)
      return false if attachment.blank?
      return false unless attachment.file.attached?
      return false unless attachment.file.variable?
      return false if attachment.respond_to?(:variants_allowed?) && !attachment.variants_allowed?

      true
    end
  end
end
