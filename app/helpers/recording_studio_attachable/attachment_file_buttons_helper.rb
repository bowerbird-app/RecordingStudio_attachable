# frozen_string_literal: true

require "recording_studio_attachable/attachment_file_button"

module RecordingStudioAttachable
  module AttachmentFileButtonsHelper
    def render_attachment_file_button(recording, return_to:, target: nil)
      render partial: "recording_studio_attachable/attachment_file_buttons/button",
             locals: AttachmentFileButton.locals(recording:, return_to:, target:)
    end

    def attachment_preview_url(recording, variant: :square_med)
      attachment_recording = AttachmentFileButton.attachment_recording_for(recording)
      return if attachment_recording.blank?

      authorized_attachment_preview_path(attachment_recording, variant)
    end

    def attachment_file_button_accept_attribute(allowed_content_types)
      AttachmentFileButton.accept_attribute(allowed_content_types)
    end
  end
end
