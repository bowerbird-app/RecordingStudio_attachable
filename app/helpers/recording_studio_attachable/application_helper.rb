# frozen_string_literal: true

module RecordingStudioAttachable
  module ApplicationHelper
    include ParentAttachmentsHelper

    def authorized_attachment_preview_path(recording, variant_name)
      attachment = recording&.recordable
      return if attachment.blank?
      return unless attachment.respond_to?(:preview_target_named)
      return if attachment.preview_target_named(variant_name).blank?

      attachable_routes.attachment_preview_file_path(recording, variant_name: variant_name)
    end

    def authorized_attachment_file_path(recording)
      attachable_routes.attachment_file_path(recording)
    end

    def parent_attachment_path(recording, **options)
      attachable_routes.parent_attachment_path(recording, **options)
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
