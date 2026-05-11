# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class ImportAttachmentPayloads < ApplicationService
      class BatchFailure < StandardError; end

      def initialize(parent_recording:, attachments:, actor: nil, impersonator: nil, context: nil)
        @parent_recording = parent_recording
        @attachments = attachments
        @actor = actor
        @impersonator = impersonator
        @context = context
      end

      private

      attr_reader :parent_recording, :attachments, :actor, :impersonator, :context

      def perform
        capability_options = capability_options_for(parent_recording)
        validate_attachment_count!(capability_options)

        created = []
        failures = nil

        begin
          transaction_wrapper do
            import_io_payloads!(created)
            finalize_blob_payloads!(created)
            import_remote_payloads!(created)
          end
        rescue BatchFailure => e
          purge_created_attachments(created)
          return failure(e.message, errors: failures || [])
        end

        success(created)
      rescue BatchFailure => e
        purge_created_attachments(created)
        failure(e.message, errors: failures || [])
      end

      def import_io_payloads!(created)
        io_payloads = attachments.select { |payload| payload[:io].present? }
        return if io_payloads.empty?

        result = RecordingStudioAttachable::Services::ImportAttachments.call(
          parent_recording: parent_recording,
          actor: actor,
          impersonator: impersonator,
          attachments: io_payloads,
          source: source_for(io_payloads.first, fallback: "provider_import")
        )

        handle_result!(result, fallback_error: "One or more attachments failed to import")
        created.concat(Array(result.value))
      end

      def finalize_blob_payloads!(created)
        blob_payloads = attachments.select { |payload| payload[:signed_blob_id].present? }
        return if blob_payloads.empty?

        result = RecordingStudioAttachable::Services::RecordAttachmentUploads.call(
          parent_recording: parent_recording,
          actor: actor,
          impersonator: impersonator,
          attachments: blob_payloads,
          default_source: source_for(blob_payloads.first, fallback: "direct_upload")
        )

        handle_result!(result, fallback_error: "One or more attachments failed to finalize")
        created.concat(Array(result.value))
      end

      def import_remote_payloads!(created)
        remote_payloads_by_provider.each do |provider, payloads|
          result = provider.import_remote_attachments(
            parent_recording: parent_recording,
            attachments: payloads,
            actor: actor,
            impersonator: impersonator,
            context: context
          )

          handle_result!(result, fallback_error: "One or more remote attachments failed to import")
          created.concat(Array(result.value))
        end
      end

      def remote_payloads_by_provider
        attachments.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |payload, grouped|
          next unless payload[:provider_payload].present?

          provider = RecordingStudioAttachable.configuration.upload_provider(payload[:provider_key])
          raise ArgumentError, "Unknown upload provider" if provider.blank?

          grouped[provider] << payload
        end
      end

      def validate_attachment_count!(capability_options)
        max_file_count = configured_capability_option(capability_options, :max_file_count)
        return if max_file_count.blank? || attachments.size <= max_file_count

        noun = max_file_count == 1 ? "file" : "files"
        raise ArgumentError, "You can upload up to #{max_file_count} #{noun} at a time"
      end

      def handle_result!(result, fallback_error:)
        return if result.success?

        raise BatchFailure, result.error.presence || fallback_error
      end

      def source_for(payload, fallback:)
        payload[:source].presence || payload[:provider_key].presence || fallback
      end

      def purge_created_attachments(created)
        Array(created).each do |recording|
          attachment = recording&.recordable
          next unless attachment.respond_to?(:file)

          blob = attachment.file&.blob
          blob.purge if blob.respond_to?(:purge)
        rescue StandardError
          next
        end
      end
    end
  end
end
