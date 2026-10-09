# frozen_string_literal: true

require_relative "placements_picker"

module RecordingStudioAttachable
  class PlacementsController < ApplicationController
    include PlacementsPicker

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

    def update
      recording = find_recording
      authorize_placement_action!(:revise, recording)
      result = Services::RevisePlacementCollection.call(
        recording: recording,
        params: params,
        actor: current_attachable_actor
      )
      redirect_to recording_placements_path(recording, attachment_navigation_params),
                  collection_flash(result)
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

    def upload_attributes(attributes)
      attributes.to_h.symbolize_keys.slice(:signed_blob_id, :name, :description, :caption, :credit, :alt_text, :file, :io)
                .compact_blank
                .then do |payload|
                  payload[:io] = payload.delete(:file) if payload[:file].present? && payload[:io].blank?
                  payload
                end
    end
  end
end
