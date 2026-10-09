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
      requested = params[:library_id].presence
      chosen = @picker_libraries.find { |library| library.id.to_s == requested.to_s } if requested
      return chosen if chosen.present?

      default = RecordingStudioAttachable.library_for(
        image_library_parent_for(@recording),
        actor: current_attachable_actor
      )
      @picker_libraries.find { |library| library.id.to_s == default.id.to_s } || @picker_libraries.first || default
    end

    def image_library_parent_for(recording)
      current = recording
      while current
        return current if RecordingStudioAttachable::Authorization.library_enabled?(recording: current)

        next_parent = current.try(:parent_recording)
        break if next_parent.blank? || next_parent == current

        current = next_parent
      end

      root_recording_for(recording)
    end

    def find_placement_recording(id = params[:id])
      recording = RecordingStudio::Recording.find(id)
      raise ActiveRecord::RecordNotFound unless Placements.placement_recording?(recording)

      recording
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
