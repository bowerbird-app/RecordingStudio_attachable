# frozen_string_literal: true

module RecordingStudioAttachable
  class PlacementsController < ApplicationController
    def index
      @recording = find_recording
      authorize_placement_action!(:view, @recording)
      @resolved = RecordingStudioAttachable::Placements.resolve(@recording)
      @picker_libraries = RecordingStudioAttachable::Placements.picker_libraries_for(@recording)
      @library = selected_picker_library
      @can_add = RecordingStudioAttachable::Authorization.placement_allowed?(
        action: :upload,
        actor: current_attachable_actor,
        recording: @recording
      )
      @can_remove = RecordingStudioAttachable::Authorization.placement_allowed?(
        action: :remove,
        actor: current_attachable_actor,
        recording: @recording
      )
      @can_reorder = @can_add && @recording.respond_to?(:recording_studio_orderable_reorder!)
    end

    def create
      recording = find_recording
      authorize_placement_action!(:upload, recording)

      result = create_placement(recording)
      redirect_to recording_placements_path(recording, attachment_navigation_params),
                  result.success? ? { notice: t("recording_studio_attachable.placements.added") } : { alert: result.error }
    end

    def reorder
      recording = find_recording
      authorize_placement_action!(:revise, recording)

      result = RecordingStudioAttachable::Services::ReorderPlacements.call(
        parent_recording: recording,
        ordered_recording_ids: params[:ordered_recording_ids],
        actor: current_attachable_actor
      )

      if request.format.json?
        return render json: { ok: result.success? }, status: result.success? ? :ok : :unprocessable_entity
      end

      redirect_to recording_placements_path(recording, attachment_navigation_params),
                  result.success? ? { notice: t("recording_studio_attachable.placements.reordered") } : { alert: result.error }
    end

    def destroy
      placement = find_placement_recording
      parent = placement.parent_recording
      authorize_placement_action!(:remove, parent)

      result = RecordingStudioAttachable::Services::RemovePlacement.call(
        parent_recording: parent,
        placement_recording: placement,
        actor: current_attachable_actor,
        impersonator: current_attachable_impersonator
      )

      redirect_to recording_placements_path(parent, attachment_navigation_params),
                  result.success? ? { notice: t("recording_studio_attachable.placements.removed") } : { alert: result.error }
    end

    private

    def create_placement(recording)
      attributes = placement_params
      if attributes[:attachment_recording_id].present?
        attachment = RecordingStudio::Recording.find(attributes[:attachment_recording_id])
        RecordingStudioAttachable::Services::PlaceLibraryImage.call(
          parent_recording: recording,
          attachment_recording: attachment,
          actor: current_attachable_actor,
          impersonator: current_attachable_impersonator
        )
      else
        RecordingStudioAttachable::Services::UploadToLibraryAndPlace.call(
          parent_recording: recording,
          library_recording: selected_library_recording(recording, attributes[:library_recording_id]),
          actor: current_attachable_actor,
          impersonator: current_attachable_impersonator,
          **upload_attributes(attributes)
        )
      end
    end

    def placement_params
      raw = params[:placement].presence || params
      raw.permit(:attachment_recording_id, :library_recording_id, :signed_blob_id, :name, :description, :caption, :credit,
                 :alt_text, :file)
    end

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

    def upload_attributes(attributes)
      attributes.to_h.symbolize_keys.slice(:signed_blob_id, :name, :description, :caption, :credit, :alt_text, :file, :io)
                .compact_blank
                .then do |payload|
                  payload[:io] = payload.delete(:file) if payload[:file].present? && payload[:io].blank?
                  payload
                end
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
