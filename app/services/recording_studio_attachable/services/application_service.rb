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
        owner_type = RecordingStudioAttachable::Authorization.owner_type_for(recording)
        return {} unless defined?(RecordingStudio) && owner_type.present?

        RecordingStudio.capability_options(:attachable, for_type: owner_type) || {}
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

      def owner_recording_for(recording)
        RecordingStudioAttachable::Authorization.owner_recording_for(recording)
      end

      def attachment_recording!(recording)
        return recording if recording&.recordable_type == "RecordingStudioAttachable::Attachment"

        raise ArgumentError, "Recording is not an attachment"
      end

      def attachment_owner_recording!(recording)
        attachment = attachment_recording!(recording)
        return attachment.parent_recording if attachment.parent_recording.present?

        raise ArgumentError, "Attachment recording must belong to a parent recording"
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

      def attachment_from_signed_blob!(signed_blob_id:, name:, description:, capability_options: {})
        blob = ActiveStorage::Blob.find_signed!(signed_blob_id)
        validate_blob!(blob, capability_options: capability_options)
        RecordingStudioAttachable::Attachment.build_from_blob(
          blob: blob,
          name: name,
          description: description,
          validation_options: capability_validation_options(capability_options)
        )
      end

      def validate_blob!(blob, capability_options: {})
        config = RecordingStudioAttachable.configuration
        validation_options = capability_validation_options(capability_options)
        raise ArgumentError, "Blob content type is not allowed" unless config.allowed_content_type?(
          blob.content_type,
          allowed_content_types: validation_options[:allowed_content_types]
        )

        max_file_size = capability_options[:max_file_size] || config.max_file_size
        raise ArgumentError, "Blob exceeds maximum file size" if max_file_size.present? && blob.byte_size > max_file_size
      end

      def capability_validation_options(capability_options)
        capability_options.to_h.slice(:allowed_content_types, :enabled_attachment_kinds)
      end

      def transaction_wrapper(&)
        if defined?(RecordingStudio::Recording) && RecordingStudio::Recording.respond_to?(:transaction)
          RecordingStudio::Recording.transaction(&)
        else
          yield
        end
      end
    end
  end
end
