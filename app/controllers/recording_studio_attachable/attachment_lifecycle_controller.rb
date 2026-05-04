# frozen_string_literal: true

module RecordingStudioAttachable
  class AttachmentLifecycleController < ApplicationController
    def bulk_destroy
      recording = find_recording
      capability_options = capability_options_for(recording)
      authorize_attachment_action!(:remove, recording, capability_options: capability_options)

      result = RecordingStudioAttachable::Services::RemoveAttachments.call(
        parent_recording: recording,
        attachment_ids: params[:attachment_ids],
        actor: current_attachable_actor
      )

      redirect_to recording_attachments_path(recording, listing_redirect_params),
                  result.success? ? { notice: "Removed #{result.value.size} attachment(s)." } : { alert: result.error }
    end

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

    def listing_redirect_params
      params.permit(:scope, :kind, :q, :page, :include_trashed).to_h.compact_blank
    end
  end
end
