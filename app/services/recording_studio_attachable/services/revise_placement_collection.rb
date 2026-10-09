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

        resolved_actor = resolve_actor(actor)
        apply_revisions(sheet, resolved_actor)
        ids = sheet.reorder_ids
        return success(sheet.revisions.any? ? :saved : recording) if ids.nil?

        outcome = ReorderPlacements.call(
          parent_recording: recording,
          ordered_recording_ids: ids,
          actor: resolved_actor
        )
        return outcome if outcome.failure?

        success(sheet.revisions.any? ? :saved : :reordered)
      end

      def apply_revisions(sheet, resolved_actor)
        sheet.revisions.each do |revision|
          result = ReviseAttachmentMetadata.call(
            attachment_recording: revision.recording,
            actor: resolved_actor,
            **revision.changes
          )
          raise ArgumentError, result.error if result.failure?
        end
      end
    end
  end
end
