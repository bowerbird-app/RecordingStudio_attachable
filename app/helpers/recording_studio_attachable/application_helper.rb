# frozen_string_literal: true

module RecordingStudioAttachable
  module ApplicationHelper
    include AttachmentFileButtonsHelper
    include AttachmentCollectionsHelper

    def authorized_attachment_preview_path(recording, variant_name)
      attachment = recording&.recordable
      return if attachment.blank?
      return unless attachment.respond_to?(:preview_target_named)
      return if attachment.preview_target_named(variant_name).blank?

      rails_url = attachable_routes.attachment_preview_file_path(recording, variant_name: variant_name)
      return rails_url unless attachment.respond_to?(:url_for_variant)

      attachment.url_for_variant(variant_name, rails_url: rails_url)
    end

    def authorized_attachment_file_path(recording)
      rails_url = attachable_routes.attachment_file_path(recording)
      attachment = recording.respond_to?(:recordable) ? recording.recordable : nil
      return rails_url unless attachment.respond_to?(:original_url)

      attachment.original_url(rails_url: rails_url)
    end

    def attachable_attachment_path(attachment_recording, **options)
      attachable_routes.attachment_path(attachment_recording, **options)
    end

    def attachable_attachment_imports_path(recording, **options)
      attachable_routes.recording_attachment_imports_path(recording, **options)
    end

    private

    def attachable_routes
      if respond_to?(:recording_studio_attachable, true)
        recording_studio_attachable
      else
        RecordingStudioAttachable::Engine.routes.url_helpers
      end
    end
  end
end
