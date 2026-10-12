# frozen_string_literal: true

module RecordingStudioAttachable
  module AttachmentFileButtonResponses
    extend ActiveSupport::Concern

    private

    def attachment_file_updated_notice
      Copy.legacy_t(
        "attachment_file_buttons.updated",
        "flashes.file_updated",
        default: "File updated"
      )
    end

    def success_notice_for(file_replacement, parent_return_to)
      return attachment_file_updated_notice if file_replacement && parent_return_to.present?

      Copy.legacy_t(
        "attachments.updated",
        "flashes.saved_short",
        default: "Saved"
      )
    end

    def success_path_for(updated_recording, file_replacement, parent_return_to, redirect_params)
      return parent_return_to if file_replacement && parent_return_to.present?
      return attachment_path(updated_recording, redirect_params) if redirect_params.present?

      attachment_path(updated_recording)
    end

    def failure_path_for(attachment_recording, file_replacement, parent_return_to, redirect_params)
      return parent_return_to if file_replacement && parent_return_to.present?
      return attachment_path(attachment_recording, redirect_params) if redirect_params.present?

      attachment_path(attachment_recording)
    end
  end
end
