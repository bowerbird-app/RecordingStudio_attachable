# frozen_string_literal: true

module RecordingStudioAttachable
  class AttachmentLifecycleController < ApplicationController
    def destroy
      attachment_recording = find_attachment_recording
      authorize_attachment_action!(:remove, attachment_recording.parent_recording || attachment_recording,
                                   capability_options: capability_options_for(attachment_recording))
      result = RecordingStudioAttachable::Services::RemoveAttachment.call(
        attachment_recording: attachment_recording,
        actor: current_attachable_actor
      )

      redirect_to fallback_listing_path(attachment_recording), result.success? ? { notice: "Attachment removed." } : { alert: result.error }
    end

    def restore
      attachment_recording = find_attachment_recording
      authorize_attachment_action!(:restore, attachment_recording.parent_recording || attachment_recording,
                                   capability_options: capability_options_for(attachment_recording))
      result = RecordingStudioAttachable::Services::RestoreAttachment.call(
        attachment_recording: attachment_recording,
        actor: current_attachable_actor
      )

      redirect_to attachment_path(attachment_recording), result.success? ? { notice: "Attachment restored." } : { alert: result.error }
    end

    private

    def fallback_listing_path(recording)
      parent = recording.parent_recording
      parent ? recording_attachments_path(parent) : main_app.root_path
    end

    def capability_options_for(recording)
      owner_type =
        if recording.recordable_type == RecordingStudioAttachable::Attachment.name
          recording.parent_recording&.recordable_type
        else
          recording.recordable_type
        end
      RecordingStudio.capability_options(:attachable, for_type: owner_type) || {}
    end
  end
end
