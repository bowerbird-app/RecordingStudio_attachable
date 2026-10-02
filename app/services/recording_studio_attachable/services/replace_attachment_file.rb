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
        owner_recording = attachment_owner_recording!(attachment_recording)
        capability_options = capability_options_for(owner_recording)
        resolved_actor = resolve_actor(actor)
        authorize!(action: :revise, actor: resolved_actor, recording: owner_recording, capability_options: capability_options)

        current_attachment = attachment_recording.recordable
        blob = signed_blob!(signed_blob_id, capability_options: capability_options)
        root_recording = root_recording_for(attachment_recording)
        incoming = RecordingStudioAttachable::StorageLimit::IncomingBytes.for(root_recording, [blob])
        event = RecordingStudioAttachable::StorageLimit.with_storage_capacity!(root_recording, incoming) do
          record_replacement(blob, current_attachment, capability_options, root_recording, resolved_actor)
        end

        success(event.recording)
      end

      def record_replacement(blob, current_attachment, capability_options, root_recording, resolved_actor)
        replacement = build_attachment!(
          blob: blob,
          name: name.presence || current_attachment.name,
          description: description.nil? ? current_attachment.description : description,
          caption: current_attachment.caption,
          credit: current_attachment.credit,
          alt_text: current_attachment.alt_text,
          capability_options: capability_options,
          root_recording: root_recording
        )
        RecordingStudio.record!(
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
      end
    end
  end
end
