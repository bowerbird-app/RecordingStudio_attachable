# frozen_string_literal: true

module RecordingStudioAttachable
  class LibrariesController < ApplicationController
    def show
      root_recording = find_recording(params[:root_recording_id])
      authorize_root_view!(root_recording)

      library = RecordingStudioAttachable.library_for(root_recording, actor: current_attachable_actor)
      redirect_to recording_attachments_path(library, kind: :images, **attachment_navigation_params)
    end

    private

    def authorize_root_view!(root_recording)
      return unless defined?(RecordingStudioAccessible::Authorization)

      allowed = RecordingStudioAccessible::Authorization.allowed?(
        actor: current_attachable_actor,
        recording: root_recording,
        role: :view
      )
      raise RecordingStudioAttachable::Authorization::NotAuthorizedError, "Not authorized to view this library" unless allowed
    end
  end
end
