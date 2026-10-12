# frozen_string_literal: true

require "recording_studio_attachable/attachment_collection"

module RecordingStudioAttachable
  module Services
    class RevisePlacementCollection < ApplicationService
      def initialize(recording:, params:, actor: nil, impersonator: nil)
        @recording = recording
        @params = params
        @actor = actor
        @impersonator = impersonator
      end

      private

      attr_reader :recording, :params, :actor, :impersonator

      def perform
        require_recording_studio!
        resolved_actor = resolve_actor(actor)
        RecordingStudioAttachable::Authorization.authorize_placement!(
          action: :revise,
          actor: resolved_actor,
          recording: recording
        )

        sheet = AttachmentCollection.from_params(recording: recording, params: params)
        raise ArgumentError, AttachmentCollection::STALE_FORM unless sheet.placement?

        apply_revisions(sheet, resolved_actor)
        reorder_placements(sheet, resolved_actor)
        success(recording)
      end

      def apply_revisions(sheet, resolved_actor)
        sheet.revisions.each do |revision|
          result = ReviseAttachmentMetadata.call(
            attachment_recording: revision.recording,
            actor: resolved_actor,
            impersonator: impersonator,
            **revision.changes
          )
          raise ArgumentError, result.error if result.failure?
        end
      end

      def reorder_placements(sheet, resolved_actor)
        ids = sheet.reorder_ids
        return if ids.nil?

        if RecordingStudioLibrary.respond_to?(:revise_placements!)
          RecordingStudioLibrary.revise_placements!(recording, ids, actor: resolved_actor)
        else
          RecordingStudioLibrary.reorder!(recording, ids, actor: resolved_actor)
        end
      end
    end
  end
end
