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
        resolved_actor = resolve_actor(actor)
        authorize!(action: :upload, actor: resolved_actor, recording: parent_recording, capability_options: capability_options)

        blob = create_blob!
        begin
          validate_blob!(blob, capability_options: capability_options)
        rescue ArgumentError => e
          RecordingStudioAttachable::StorageLimit.discard_unattached!([blob])
          return failure(e.message)
        end

        with_around_attach(parent_recording: parent_recording, actor: resolved_actor, blobs: [blob]) do
          result = RecordAttachmentUpload.call(
            parent_recording: parent_recording,
            signed_blob_id: DirectUpload.sign(blob),
            actor: actor,
            impersonator: impersonator,
            name: resolved_name,
            description: description,
            metadata: import_metadata
          )
          raise ArgumentError, result.error if result.failure?

          success(result.value)
        end
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
    end
  end
end
