# frozen_string_literal: true

require "securerandom"

module RecordingStudioAttachable
  module Services
    class RecordAttachmentUploads < ApplicationService
      class BatchFailure < StandardError; end

      def initialize(parent_recording:, attachments:, actor: nil, impersonator: nil, default_source: "direct_upload")
        @parent_recording = parent_recording
        @attachments = attachments
        @actor = actor
        @impersonator = impersonator
        @default_source = default_source
      end

      private

      attr_reader :parent_recording, :attachments, :actor, :impersonator, :default_source

      def perform
        capability_options = capability_options_for(parent_recording)
        validate_attachment_count!(capability_options)

        batch_id = SecureRandom.uuid
        created = []
        failures = nil

        begin
          transaction_wrapper do
            Array(attachments).each do |payload|
              result = RecordAttachmentUpload.call(
                parent_recording: parent_recording,
                signed_blob_id: payload.fetch(:signed_blob_id),
                name: payload[:name],
                description: payload[:description],
                actor: actor,
                impersonator: impersonator,
                batch_id: batch_id,
                metadata: payload_metadata(payload)
              )

              if result.failure?
                failures = [payload.merge(error: result.error)]
                raise BatchFailure, result.error
              end

              created << result.value
            end
          end
        rescue BatchFailure
          return failure("One or more attachments failed to finalize", errors: failures)
        end

        success(created)
      end

      def validate_attachment_count!(capability_options)
        max_file_count = configured_capability_option(capability_options, :max_file_count)
        return if max_file_count.blank? || Array(attachments).size <= max_file_count

        noun = max_file_count == 1 ? "file" : "files"
        raise ArgumentError, "You can upload up to #{max_file_count} #{noun} at a time"
      end

      def payload_metadata(payload)
        payload.fetch(:metadata, {}).to_h.merge(source: payload[:source].presence || default_source)
      end
    end
  end
end
