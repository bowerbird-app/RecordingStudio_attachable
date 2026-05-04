# frozen_string_literal: true

require "securerandom"

module RecordingStudioAttachable
  module Services
    class RecordAttachmentUploads < ApplicationService
      class BatchFailure < StandardError; end

      def initialize(parent_recording:, attachments:, actor: nil, impersonator: nil)
        @parent_recording = parent_recording
        @attachments = attachments
        @actor = actor
        @impersonator = impersonator
      end

      private

      attr_reader :parent_recording, :attachments, :actor, :impersonator

      def perform
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
                batch_id: batch_id
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
    end
  end
end
