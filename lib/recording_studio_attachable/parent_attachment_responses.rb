# frozen_string_literal: true

module RecordingStudioAttachable
  module ParentAttachmentResponses
    extend ActiveSupport::Concern

    private

    def parent_attachment_replaced_notice
      I18n.t("recording_studio_attachable.parent_attachments.replaced", default: "File updated")
    end

    def success_notice_for(file_replacement, parent_return_to)
      return parent_attachment_replaced_notice if file_replacement && parent_return_to.present?

      I18n.t("recording_studio_attachable.attachments.updated", default: "Saved")
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

    def render_parent_attachment_slot_stream(recording:, return_to:, shape: ParentAttachmentSlot::DEFAULT_SHAPE,
                                            size: ParentAttachmentSlot::DEFAULT_SIZE)
      turbo_stream.replace(
        ParentAttachmentSlot.frame_dom_id(recording),
        partial: "recording_studio_attachable/parent_attachments/frame",
        locals: {
          recording: recording,
          return_to: return_to,
          shape: shape,
          size: size
        }
      )
    end
  end
end
