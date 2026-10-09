# frozen_string_literal: true

require "recording_studio_attachable/attachment_collection"

module RecordingStudioAttachable
  module Services
    class RevisePlacementCollection < ApplicationService
      def initialize(recording:, params:, actor: nil)
        @recording = recording
        @params = params
        @actor = actor
      end

      private

      attr_reader :recording, :params, :actor

      def perform
        sheet = AttachmentCollection.from_params(recording: recording, params: AttachmentCollection.permit(params))
        raise ArgumentError, AttachmentCollection::STALE_FORM unless sheet.placement?

        ids = sheet.reorder_ids
        return success(recording) if ids.nil?

        outcome = ReorderPlacements.call(
          parent_recording: recording,
          ordered_recording_ids: ids,
          actor: resolve_actor(actor)
        )
        return outcome if outcome.failure?

        success(:reordered)
      end
    end
  end
end
