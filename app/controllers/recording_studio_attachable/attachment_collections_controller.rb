# frozen_string_literal: true

module RecordingStudioAttachable
  class AttachmentCollectionsController < ApplicationController
    def update
      recording = find_recording
      authorize_attachment_action!(:revise, recording, capability_options: capability_options_for(recording))
      result = revise_collection(recording)
      redirect_to collection_destination(recording), **collection_flash(result)
    end

    private

    def revise_collection(recording)
      Services::ReviseAttachmentCollection.call(
        recording: recording,
        params: AttachmentCollection.permit(params),
        actor: current_attachable_actor,
        impersonator: current_attachable_impersonator
      )
    end

    def collection_destination(recording)
      AttachmentFileButton.return_to_from(attachment_redirect_params).presence || recording_attachments_path(recording)
    end

    def collection_flash(result)
      return { status: :see_other, notice: "Saved." } if result.success?

      { status: :see_other, alert: result.error }
    end
  end
end
