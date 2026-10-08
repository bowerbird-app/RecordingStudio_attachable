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
      return if attachment.blank?
      return unless attachment.file.attached?
      return unless attachment.file.variable?

      RecordingStudioAttachable.configuration.preprocessed_variants.each do |variant_name|
        transformations = RecordingStudioAttachable.configuration.image_variant(variant_name)
        next if transformations.blank?

        attachment.file.variant(transformations).processed
      end
    end
  end
end
