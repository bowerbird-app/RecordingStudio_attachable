# frozen_string_literal: true

module RecordingStudioAttachable
  module AttachmentChromeResponses
    extend ActiveSupport::Concern

    private

    def attachment_chrome_replaced_notice
      I18n.t("recording_studio_attachable.attachment_chromes.replaced", default: "File updated")
    end

    def success_notice_for(file_replacement, parent_return_to)
      return attachment_chrome_replaced_notice if file_replacement && parent_return_to.present?

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

    def attachment_chrome_from_params
      AttachmentChrome.from_params(params)
    end

    def render_attachment_chrome_stream(recording:, return_to:, chrome:)
      turbo_stream.replace(
        AttachmentChrome.frame_dom_id(recording, kind: chrome.fetch(:kind)),
        partial: "recording_studio_attachable/attachment_chromes/frame",
        locals: stream_locals_for(recording, return_to, chrome)
      )
    end

    def stream_locals_for(recording, return_to, chrome)
      {
        recording: recording,
        return_to: return_to,
        kind: chrome.fetch(:kind),
        shape: chrome.fetch(:shape),
        size: chrome.fetch(:size),
        add_label: chrome.fetch(:add_label),
        change_label: chrome.fetch(:change_label)
      }
    end
  end
end
