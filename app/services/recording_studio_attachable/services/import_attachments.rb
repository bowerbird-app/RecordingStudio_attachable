# frozen_string_literal: true

require "securerandom"

module RecordingStudioAttachable
  module Services
    class ImportAttachments < ApplicationService
      class BatchFailure < StandardError; end

      def initialize(parent_recording:, attachments:, actor: nil, impersonator: nil, source: "provider_import")
        @parent_recording = parent_recording
        @attachments = attachments
        @actor = actor
        @impersonator = impersonator
        @source = source
      end

      private

      attr_reader :parent_recording, :attachments, :actor, :impersonator, :source

      def perform
        capability_options = capability_options_for(parent_recording)
        validate_attachment_count!(capability_options)

        batch_id = SecureRandom.uuid
        created = []
        failures = nil

        begin
          transaction_wrapper do
            Array(attachments).each do |attachment|
              result = ImportAttachment.call(
                parent_recording: parent_recording,
                actor: actor,
                impersonator: impersonator,
                io: attachment.fetch(:io),
                filename: attachment.fetch(:filename),
                content_type: attachment.fetch(:content_type),
                name: attachment[:name],
                description: attachment[:description],
                identify: attachment.fetch(:identify, true),
                metadata: attachment.fetch(:metadata, {}).merge(batch_id: batch_id),
                source: attachment[:source] || source,
                service_name: attachment[:service_name]
              )

              if result.failure?
                failures = [attachment.except(:io).merge(error: result.error)]
                raise BatchFailure, batch_failure_message(attachment, result.error)
              end

              created << result.value
            end
          end
        rescue BatchFailure => e
          purge_created_attachments(created)
          return failure(e.message, errors: failures)
        end

        success(created)
      end

      def batch_failure_message(attachment, error)
        label = attachment[:name].presence || attachment[:filename].presence
        return error if label.blank?

        %(Failed to import "#{label}": #{error})
      end

      def validate_attachment_count!(capability_options)
        max_file_count = configured_capability_option(capability_options, :max_file_count)
        return if max_file_count.blank? || Array(attachments).size <= max_file_count

        noun = max_file_count == 1 ? "file" : "files"
        raise ArgumentError, "You can import up to #{max_file_count} #{noun} at a time"
      end

      def purge_created_attachments(created)
        Array(created).each do |recording|
          attachment = recording&.recordable
          next unless attachment.respond_to?(:file)

          file = attachment.file
          blob = file&.blob
          next unless blob.respond_to?(:purge)

          blob.purge
        rescue StandardError
          next
        end
      end
    end
  end
end
