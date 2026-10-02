# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class ReviseAttachmentCollection < ApplicationService
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
        authorize!(action: :revise, actor: resolved_actor, recording: recording)
        transaction_wrapper { apply(resolved_actor) }
        success(recording)
      end

      def apply(resolved_actor)
        sheet = AttachmentCollection.from_params(recording: recording, params: params)
        revise_each(sheet, resolved_actor)
        reorder(sheet, resolved_actor)
      end

      def revise_each(sheet, resolved_actor)
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

      def reorder(sheet, resolved_actor)
        ordered_ids = sheet.reorder_ids
        return if ordered_ids.nil?

        recording.recording_studio_orderable_reorder!(ordered_recording_ids: ordered_ids, actor: resolved_actor)
      end
    end
  end
end
