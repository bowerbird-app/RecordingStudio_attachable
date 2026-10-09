# frozen_string_literal: true

module RecordingStudioAttachable
  module PlacementsPicker
    private

    def selected_library_recording(parent, library_id)
      return if library_id.blank?

      library = RecordingStudio::Recording.find(library_id)
      return unless Placements.library_recording?(library)
      return unless Placements.picker_libraries_for(parent).any? { |item| item.id.to_s == library.id.to_s }

      library
    end

    def selected_picker_library
      return if @picker_libraries.blank?

      requested = params[:library_id].presence
      chosen = @picker_libraries.find { |library| library.id.to_s == requested.to_s } if requested
      chosen || @picker_libraries.first
    end

    def find_placement_recording(id = params[:id])
      recording = RecordingStudio::Recording.find(id)
      raise ActiveRecord::RecordNotFound unless Placements.placement_recording?(recording)

      recording
    end

    def collection_flash(result)
      return { alert: result.error } unless result.success?
      return { notice: t("recording_studio_attachable.placements.reordered") } if result.value == :reordered

      { notice: t("recording_studio_attachable.attachments.updated") }
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

    def authorize_placement_action!(action, recording)
      RecordingStudioAttachable::Authorization.authorize_placement!(
        action: action,
        actor: current_attachable_actor,
        recording: recording
      )
    end

    def root_recording_for(recording)
      recording.respond_to?(:root_recording) ? (recording.root_recording || recording) : recording
    end
  end
end
