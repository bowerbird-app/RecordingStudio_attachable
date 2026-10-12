# frozen_string_literal: true

module RecordingStudioAttachable
  class AttachmentCollectionsController < ApplicationController
    def update
      recording = find_recording
      authorize_attachment_action!(:revise, recording, capability_options: capability_options_for(recording))
      result = revise_collection(recording)
      return render_slide_save(result) if stay_on_slide?

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
      return { status: :see_other, notice: Copy.t("flashes.saved", default: "Saved.") } if result.success?

      { status: :see_other, alert: result.error }
    end

    def stay_on_slide?
      params[:stay] == "slide" && request.xhr? && request.format.json?
    end

    def render_slide_save(result)
      if result.success?
        render json: { saved: true }, status: :ok
        return
      end

      render json: {
        saved: false,
        error: result.error.presence || Copy.t("flashes.could_not_save", default: "Could not save.")
      }, status: :unprocessable_entity
    end
  end
end
