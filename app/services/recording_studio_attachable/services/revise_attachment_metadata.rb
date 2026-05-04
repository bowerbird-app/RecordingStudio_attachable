# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class ReviseAttachmentMetadata < ApplicationService
      def initialize(attachment_recording:, actor: nil, impersonator: nil, name: nil, description: nil, metadata: {})
        @attachment_recording = attachment_recording
        @actor = actor
        @impersonator = impersonator
        @name = name
        @description = description
        @metadata = metadata
      end

      private

      attr_reader :attachment_recording, :actor, :impersonator, :name, :description, :metadata

      def perform
        require_recording_studio!
        owner_recording = attachment_owner_recording!(attachment_recording)
        capability_options = capability_options_for(owner_recording)
        resolved_actor = resolve_actor(actor)
        authorize!(action: :revise, actor: resolved_actor, recording: owner_recording, capability_options: capability_options)

        attachment = attachment_recording.recordable
        revised = RecordingStudioAttachable::Attachment.build_from_blob(
          blob: attachment.file.blob,
          name: name.presence || attachment.name,
          description: description.nil? ? attachment.description : description,
          validation_options: capability_validation_options(capability_options)
        )
        root_recording = root_recording_for(attachment_recording)
        event = RecordingStudio.record!(
          action: "attachment_metadata_revised",
          recordable: revised,
          recording: attachment_recording,
          root_recording: root_recording,
          actor: resolved_actor,
          impersonator: impersonator,
          metadata: metadata_for(
            attachment: revised,
            extra: metadata.merge(
              attachment_recording_id: attachment_recording.id,
              parent_recording_id: attachment_recording.parent_recording_id,
              root_recording_id: root_recording.id,
              previous_attachment_recordable_id: attachment.id,
              source: "metadata_revision"
            )
          )
        )

        success(event.recording)
      end
    end
  end
end
