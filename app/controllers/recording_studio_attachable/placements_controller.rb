# frozen_string_literal: true

module RecordingStudioAttachable
  class PlacementsController < ApplicationController
    def index
      recording = find_recording(params[:recording_id])
      redirect_to library_engine.recording_placements_path(recording, **library_redirect_params), status: :see_other
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
  end
end
