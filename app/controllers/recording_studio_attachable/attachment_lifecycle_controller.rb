# frozen_string_literal: true

module RecordingStudioAttachable
  class AttachmentLifecycleController < ApplicationController
    def destroy
      attachment_recording = find_attachment_recording
      authorize_attachment_owner_action!(:remove, attachment_recording)

      result = RecordingStudioAttachable::Services::RemoveAttachment.call(
        attachment_recording: attachment_recording,
        actor: current_attachable_actor
      )

      redirect_to fallback_listing_path(attachment_recording), result.success? ? { notice: "Attachment removed." } : { alert: result.error }
    end

    def restore
      attachment_recording = find_attachment_recording
      authorize_attachment_owner_action!(:restore, attachment_recording)

      result = RecordingStudioAttachable::Services::RestoreAttachment.call(
        attachment_recording: attachment_recording,
        actor: current_attachable_actor
      )

      redirect_to attachment_path(attachment_recording), result.success? ? { notice: "Attachment restored." } : { alert: result.error }
    end

    private

    def fallback_listing_path(recording)
      parent = attachable_owner_recording(recording)
      parent ? recording_attachments_path(parent) : main_app.root_path
    end
  end
end
