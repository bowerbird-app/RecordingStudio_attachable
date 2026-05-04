# frozen_string_literal: true

require "securerandom"

module RecordingStudioAttachable
  module Services
    class RecordAttachmentUploads < ApplicationService
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
        failures = []

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

          if result.success?
            created << result.value
          else
            failures << payload.merge(error: result.error)
          end
        end

        return success(created) if failures.empty?

        failure("One or more attachments failed to finalize", errors: failures)
      end
    end
  end
end
