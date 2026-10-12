# frozen_string_literal: true

module RecordingStudioAttachable
  class LibrariesController < ApplicationController
    def show
      recording = find_recording(params[:id] || params[:recording_id] || params[:root_recording_id])
      library = library_from(recording)
      redirect_to library_engine.library_path(library, **library_redirect_params), status: :see_other
    end

    private

    def library_from(recording)
      return recording if Placements.library_recording?(recording)

      RecordingStudioAttachable.library_for(
        recording,
        key: params[:key].presence || :default,
        actor: current_attachable_actor
      )
    end

    def library_engine
      main_app.recording_studio_library
    end

    def library_redirect_params
      {
        redirect_mode: params[:redirect_mode].presence,
        return_to: params[:return_to].presence
      }.compact
    end
  end
end
