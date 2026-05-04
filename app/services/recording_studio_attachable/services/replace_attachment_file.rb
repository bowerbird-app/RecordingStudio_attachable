# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class ReplaceAttachmentFile < ApplicationService
      def initialize(attachment_recording:, signed_blob_id:, actor: nil, impersonator: nil, name: nil, description: nil,
                     metadata: {})
        @attachment_recording = attachment_recording
        @signed_blob_id = signed_blob_id
        @actor = actor
        @impersonator = impersonator
        @name = name
        @description = description
        @metadata = metadata
      end

      private

      attr_reader :attachment_recording, :signed_blob_id, :actor, :impersonator, :name, :description, :metadata

      def perform
        require_recording_studio!
        resolved_actor = resolve_actor(actor)
        authorize!(action: :revise, actor: resolved_actor, recording: attachment_recording.parent_recording || attachment_recording)

        current_attachment = attachment_recording.recordable
        replacement = attachment_from_signed_blob!(
          signed_blob_id: signed_blob_id,
          name: name.presence || current_attachment.name,
          description: description.nil? ? current_attachment.description : description
        )
        root_recording = root_recording_for(attachment_recording)
        event = RecordingStudio.record!(
          action: "attachment_file_replaced",
          recordable: replacement,
          recording: attachment_recording,
          root_recording: root_recording,
          actor: resolved_actor,
          impersonator: impersonator,
          metadata: metadata_for(
            attachment: replacement,
            extra: metadata.merge(
              attachment_recording_id: attachment_recording.id,
              parent_recording_id: attachment_recording.parent_recording_id,
              root_recording_id: root_recording.id,
              previous_attachment_recordable_id: current_attachment.id,
              source: "file_replacement"
            )
          )
        )

        success(event.recording)
      end
    end
  end
end
