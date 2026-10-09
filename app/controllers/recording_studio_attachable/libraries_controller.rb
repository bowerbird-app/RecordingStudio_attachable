# frozen_string_literal: true

module RecordingStudioAttachable
  class LibrariesController < ApplicationController
    def show
      recording = find_recording(params[:id] || params[:recording_id] || params[:root_recording_id])
      authorize_library_action!(:view, recording)
      library = library_from(recording)
      redirect_to recording_attachments_path(library, kind: :images, **attachment_navigation_params)
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

    def authorize_library_action!(action, recording)
      RecordingStudioAttachable::Authorization.authorize_library!(
        action: action,
        actor: current_attachable_actor,
        recording: recording
      )
    end
  end
end
