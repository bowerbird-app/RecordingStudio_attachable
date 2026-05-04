# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class ApplicationService < BaseService
      private

      def require_recording_studio!
        return if defined?(RecordingStudio)

        raise RecordingStudioAttachable::DependencyUnavailableError, "RecordingStudio must be loaded to use RecordingStudioAttachable"
      end

      def resolve_actor(explicit_actor)
        explicit_actor || (defined?(Current) && Current.respond_to?(:actor) ? Current.actor : nil)
      end

      def capability_options_for(recording)
        return {} unless defined?(RecordingStudio) && recording.respond_to?(:recordable_type)

        RecordingStudio.capability_options(:attachable, for_type: recording.recordable_type) || {}
      end

      def authorize!(action:, actor:, recording:, capability_options: capability_options_for(recording))
        RecordingStudioAttachable::Authorization.authorize!(
          action: action,
          actor: actor,
          recording: recording,
          capability_options: capability_options
        )
      end

      def root_recording_for(recording)
        recording.root_recording || recording
      end

      def metadata_for(attachment:, extra: {})
        {
          attachment_recording_id: extra[:attachment_recording_id],
          parent_recording_id: extra[:parent_recording_id],
          root_recording_id: extra[:root_recording_id],
          attachment_recordable_id: attachment.id,
          previous_attachment_recordable_id: extra[:previous_attachment_recordable_id],
          attachment_kind: attachment.attachment_kind,
          name: attachment.name,
          original_filename: attachment.original_filename,
          content_type: attachment.content_type,
          byte_size: attachment.byte_size,
          batch_id: extra[:batch_id],
          source: extra[:source] || "direct_upload"
        }.compact
      end

      def attachment_from_signed_blob!(signed_blob_id:, name:, description:)
        blob = ActiveStorage::Blob.find_signed!(signed_blob_id)
        validate_blob!(blob)
        RecordingStudioAttachable::Attachment.build_from_blob(blob: blob, name: name, description: description)
      end

      def validate_blob!(blob)
        config = RecordingStudioAttachable.configuration
        raise ArgumentError, "Blob content type is not allowed" unless config.allowed_content_type?(blob.content_type)
        raise ArgumentError, "Blob exceeds maximum file size" if config.max_file_size.present? && blob.byte_size > config.max_file_size
      end
    end
  end
end
