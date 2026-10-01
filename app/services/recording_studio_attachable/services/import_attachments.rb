# frozen_string_literal: true

require "securerandom"

module RecordingStudioAttachable
  module Services
    class ImportAttachments < ApplicationService
      class BatchFailure < StandardError
        attr_reader :details

        def initialize(message = nil, details: nil)
          @details = details
          super(message)
        end
      end

      def initialize(parent_recording:, attachments:, actor: nil, impersonator: nil, source: "provider_import")
        @parent_recording = parent_recording
        @attachments = attachments
        @actor = actor
        @impersonator = impersonator
        @source = source
        @staged_blobs = []
        @created = []
      end

      private

      attr_reader :parent_recording, :attachments, :actor, :impersonator, :source

      def perform
        capability_options = capability_options_for(parent_recording)
        validate_attachment_count!(capability_options)
        success(import_staged(stage_attachments(capability_options)))
      rescue ArgumentError => e
        RecordingStudioAttachable::StorageLimit.discard_unattached!(@staged_blobs)
        failure(e.message)
      rescue BatchFailure => e
        RecordingStudioAttachable::StorageLimit.discard_unattached!(@staged_blobs)
        purge_created_attachments(@created)
        failure(e.message, errors: e.details)
      end

      def import_staged(staged)
        @staged_blobs = staged.map { |entry| entry[:blob] }
        batch_id = SecureRandom.uuid
        root_recording = root_recording_for(parent_recording)
        incoming = RecordingStudioAttachable::StorageLimit::IncomingBytes.for(root_recording, @staged_blobs)
        RecordingStudioAttachable::StorageLimit.with_storage_capacity!(root_recording, incoming) do
          transaction_wrapper { record_entries(staged, batch_id) }
        end
        @created
      end

      def record_entries(staged, batch_id)
        staged.each do |entry|
          result = RecordAttachmentUpload.call(
            parent_recording: parent_recording, signed_blob_id: entry[:blob].signed_id, actor: actor,
            impersonator: impersonator, name: entry[:name], description: entry[:description],
            batch_id: batch_id, metadata: entry[:metadata].merge(batch_id: batch_id)
          )
          failure = [entry[:payload].except(:io).merge(error: result.error)]
          raise BatchFailure.new(batch_failure_message(entry[:payload], result.error), details: failure) if result.failure?

          @created << result.value
        end
      end

      def stage_attachments(capability_options)
        Array(attachments).each_with_object([]) do |attachment, staged|
          staged << stage_attachment(attachment, capability_options, staged)
        end
      end

      def stage_attachment(attachment, capability_options, staged)
        blob = create_imported_blob!(
          io: attachment.fetch(:io),
          filename: attachment.fetch(:filename),
          content_type: attachment.fetch(:content_type),
          identify: attachment.fetch(:identify, true),
          service_name: attachment[:service_name]
        )
        validate_blob!(blob, capability_options: capability_options)
        {
          blob: blob, payload: attachment, name: resolved_import_name(attachment),
          description: attachment[:description],
          metadata: attachment.fetch(:metadata, {}).merge(source: attachment[:source] || source)
        }
      rescue ArgumentError => e
        @staged_blobs = staged.map { |entry| entry[:blob] } + [blob]
        details = [attachment.except(:io).merge(error: e.message)]
        raise BatchFailure.new(batch_failure_message(attachment, e.message), details: details)
      end

      def resolved_import_name(attachment)
        attachment[:name].presence || File.basename(attachment.fetch(:filename).to_s, File.extname(attachment.fetch(:filename).to_s))
      end

      def batch_failure_message(attachment, error)
        label = attachment[:name].presence || attachment[:filename].presence
        label.blank? ? error : %(Failed to import "#{label}": #{error})
      end

      def validate_attachment_count!(capability_options)
        max_file_count = configured_capability_option(capability_options, :max_file_count)
        return if max_file_count.blank? || Array(attachments).size <= max_file_count

        noun = max_file_count == 1 ? "file" : "files"
        raise ArgumentError, "You can import up to #{max_file_count} #{noun} at a time"
      end

      def purge_created_attachments(created)
        blobs = Array(created).filter_map do |recording|
          attachment = recording&.recordable
          next unless attachment.respond_to?(:file)

          attachment.file&.blob
        end
        RecordingStudioAttachable::StorageLimit.discard_unattached!(blobs)
      end
    end
  end
end
