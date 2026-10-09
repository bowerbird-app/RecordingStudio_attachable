# frozen_string_literal: true

module RecordingStudioAttachable
  class LibrariesController < ApplicationController
    def index
      @parent_recording = find_recording
      authorize_library_action!(:view, @parent_recording)
      @libraries = RecordingStudioAttachable.libraries_for(@parent_recording)
      @can_manage = RecordingStudioAttachable::Authorization.library_allowed?(
        action: :upload,
        actor: current_attachable_actor,
        recording: @parent_recording
      )
      @can_remove = RecordingStudioAttachable::Authorization.library_allowed?(
        action: :remove,
        actor: current_attachable_actor,
        recording: @parent_recording
      )
      @library_usages = @libraries.to_h { |library| [library.id.to_s, Placements.usage_for_library(library)] }
    end

    def show
      recording = find_recording(params[:id] || params[:root_recording_id])
      authorize_library_action!(:view, recording)
      library = library_from(recording)
      redirect_to recording_attachments_path(library, kind: :images, **attachment_navigation_params)
    end

    def create
      parent = find_recording
      authorize_library_action!(:upload, parent)

      result = RecordingStudioAttachable::Services::CreateLibrary.call(
        parent_recording: parent,
        name: library_params[:name],
        description: library_params[:description],
        actor: current_attachable_actor
      )

      redirect_to recording_libraries_path(parent, attachment_navigation_params),
                  result.success? ? { notice: t("recording_studio_attachable.libraries.created") } : { alert: result.error }
    end

    def update
      library = find_library_recording
      authorize_library_action!(:revise, library)

      result = RecordingStudioAttachable::Services::RenameLibrary.call(
        library_recording: library,
        name: library_params[:name],
        description: library_params.key?(:description) ? library_params[:description] : :keep,
        actor: current_attachable_actor
      )

      redirect_to recording_libraries_path(library_parent(library), attachment_navigation_params),
                  result.success? ? { notice: t("recording_studio_attachable.libraries.renamed") } : { alert: result.error }
    end

    def destroy
      library = find_library_recording
      parent = library_parent(library)
      authorize_library_action!(:remove, library)

      result = RecordingStudioAttachable::Services::TrashLibrary.call(
        library_recording: library,
        actor: current_attachable_actor,
        impersonator: current_attachable_impersonator
      )

      redirect_to recording_libraries_path(parent, attachment_navigation_params),
                  result.success? ? { notice: t("recording_studio_attachable.libraries.trashed") } : { alert: result.error }
    end

    private

    def library_from(recording)
      return recording if Placements.library_recording?(recording)

      RecordingStudioAttachable.library_for(recording, actor: current_attachable_actor)
    end

    def find_library_recording(id = params[:id])
      recording = find_recording(id)
      raise ActiveRecord::RecordNotFound unless Placements.library_recording?(recording)

      recording
    end

    def library_parent(library)
      library.try(:parent_recording) || library
    end

    def library_params
      raw = params[:library].presence || params
      raw.permit(:name, :description)
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
