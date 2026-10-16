# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class ImportAttachment < ApplicationService
      def initialize(parent_recording:, io:, filename:, content_type:, actor: nil, impersonator: nil, name: nil,
                     description: nil, metadata: {}, source: "provider_import", service_name: nil)
        @parent_recording = parent_recording
        @io = io
        @filename = filename
        @content_type = content_type
        @actor = actor
        @impersonator = impersonator
        @name = name
        @description = description
        @metadata = metadata
        @source = source
        @service_name = service_name
      end

      private

      attr_reader :parent_recording, :io, :filename, :content_type, :actor, :impersonator, :name, :description,
                  :metadata, :source, :service_name

      def perform
        capability_options = capability_options_for(parent_recording)
        authorize!(action: :upload, actor: resolve_actor(actor), recording: parent_recording, capability_options: capability_options)

        blob = create_blob!
        validate_blob!(blob, capability_options: capability_options)
        result = RecordAttachmentUpload.call(
          parent_recording: parent_recording,
          signed_blob_id: DirectUpload.sign(blob),
          actor: actor,
          impersonator: impersonator,
          name: resolved_name,
          description: description,
          metadata: import_metadata
        )

        if result.failure?
          purge_blob(blob)
          return result
        end

        success(result.value)
      rescue ArgumentError => e
        purge_blob(blob)
        failure(e.message)
      end

      def create_blob!
        create_imported_blob!(
          io: io,
          filename: filename,
          content_type: content_type,
          service_name: service_name,
          metadata: DirectUpload.metadata_for(recording: parent_recording, actor: resolve_actor(actor))
        )
      end

      def resolved_name
        return name if name.present?

        File.basename(filename.to_s, File.extname(filename.to_s))
      end

      def import_metadata
        metadata.merge(source: source)
      end

      def purge_blob(blob)
        RecordingStudioAttachable::StorageLimit.discard_unattached!([blob])
      end
    end
  end
end
