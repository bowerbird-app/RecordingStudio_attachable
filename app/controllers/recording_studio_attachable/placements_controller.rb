# frozen_string_literal: true

require "recording_studio_attachable/attachment_collection"

module RecordingStudioAttachable
  class PlacementsController < ApplicationController
    def index
      recording = find_recording(params[:recording_id])
      redirect_to library_engine.recording_placements_path(recording, **library_redirect_params), status: :see_other
    end

    def update
      recording = find_recording(params[:recording_id])
      RecordingStudioAttachable::Authorization.authorize_placement!(
        action: :revise,
        actor: current_attachable_actor,
        recording: recording
      )
      result = Services::RevisePlacementCollection.call(
        recording: recording,
        params: AttachmentCollection.permit(params),
        actor: current_attachable_actor,
        impersonator: current_attachable_impersonator
      )
      return render_slide_save(result) if stay_on_slide?

      redirect_to collection_destination(recording), **collection_flash(result)
    end

    private

    def library_engine
      main_app.recording_studio_library
    end

    def library_redirect_params
      {
        redirect_mode: params[:redirect_mode].presence,
        return_to: params[:return_to].presence,
        modal: params[:modal].presence,
        modal_id: params[:modal_id].presence
      }.compact
    end

    def collection_destination(recording)
      AttachmentFileButton.return_to_from(attachment_redirect_params).presence ||
        library_engine.recording_placements_path(recording, **library_redirect_params)
    end

    def collection_flash(result)
      return { status: :see_other, notice: "Saved." } if result.success?

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

      render json: { saved: false, error: result.error.presence || "Could not save." }, status: :unprocessable_entity
    end
  end
end
