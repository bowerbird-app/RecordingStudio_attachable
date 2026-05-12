# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class RecordAttachmentUpload < ApplicationService
      def initialize(parent_recording:, signed_blob_id:, actor: nil, impersonator: nil, name: nil, description: nil,
                     batch_id: nil, metadata: {})
        @parent_recording = parent_recording
        @signed_blob_id = signed_blob_id
        @actor = actor
        @impersonator = impersonator
        @name = name
        @description = description
        @batch_id = batch_id
        @metadata = metadata
      end

      private

      attr_reader :parent_recording, :signed_blob_id, :actor, :impersonator, :name, :description, :batch_id, :metadata

      def perform
        require_recording_studio!
        resolved_actor = resolve_actor(actor)
        capability_options = capability_options_for(parent_recording)
        authorize!(action: :upload, actor: resolved_actor, recording: parent_recording, capability_options: capability_options)

        attachment = attachment_from_signed_blob!(
          signed_blob_id: signed_blob_id,
          name: name,
          description: description,
          capability_options: capability_options
        )
        root_recording = root_recording_for(parent_recording)
        event = RecordingStudio.record!(
          action: "attachment_uploaded",
          recordable: attachment,
          root_recording: root_recording,
          parent_recording: parent_recording,
          actor: resolved_actor,
          impersonator: impersonator,
          metadata: metadata_for(
            attachment: attachment,
            extra: metadata.merge(parent_recording_id: parent_recording.id, root_recording_id: root_recording.id, batch_id: batch_id)
          )
        )

        success(event.recording)
      end
    end
  end
end
