# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class RestoreAttachment < ApplicationService
      def initialize(attachment_recording:, actor: nil, impersonator: nil, metadata: {})
        @attachment_recording = attachment_recording
        @actor = actor
        @impersonator = impersonator
        @metadata = metadata
      end

      private

      attr_reader :attachment_recording, :actor, :impersonator, :metadata

      def perform
        require_recording_studio!
        owner_recording = attachment_owner_recording!(attachment_recording)
        unless attachment_recording.respond_to?(:recording_studio_trashable_restore!)
          raise ArgumentError, "Restore requires RecordingStudio Trashable"
        end

        resolved_actor = resolve_actor(actor)
        capability_options = capability_options_for(owner_recording)
        authorize!(action: :restore, actor: resolved_actor, recording: owner_recording, capability_options: capability_options)

        attachment_recording.recording_studio_trashable_restore!(actor: resolved_actor, impersonator: impersonator)
        attachment_recording.log_event!(
          action: "attachment_restored",
          actor: resolved_actor,
          impersonator: impersonator,
          metadata: metadata_for(
            attachment: attachment_recording.recordable,
            extra: metadata.merge(
              attachment_recording_id: attachment_recording.id,
              parent_recording_id: attachment_recording.parent_recording_id,
              root_recording_id: root_recording_for(attachment_recording).id,
              source: "restore"
            )
          )
        )

        success(attachment_recording)
      end
    end
  end
end
