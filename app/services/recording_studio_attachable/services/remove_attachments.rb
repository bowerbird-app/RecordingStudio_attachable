# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class RemoveAttachments < ApplicationService
      class BatchFailure < StandardError; end

      def initialize(parent_recording:, attachment_ids: nil, attachment_recordings: nil, actor: nil, impersonator: nil,
                     metadata: {})
        @parent_recording = parent_recording
        @attachment_ids = attachment_ids
        @attachment_recordings = attachment_recordings
        @actor = actor
        @impersonator = impersonator
        @metadata = metadata
      end

      private

      attr_reader :parent_recording, :attachment_ids, :attachment_recordings, :actor, :impersonator, :metadata

      def perform
        require_recording_studio!
        resolved_actor = resolve_actor(actor)
        capability_options = capability_options_for(parent_recording)
        authorize!(action: :remove, actor: resolved_actor, recording: parent_recording, capability_options: capability_options)

        selected_attachments = selected_attachment_recordings
        removed = []
        failures = nil

        begin
          transaction_wrapper do
            selected_attachments.each do |attachment_recording|
              result = RemoveAttachment.call(
                attachment_recording: attachment_recording,
                actor: resolved_actor,
                impersonator: impersonator,
                metadata: metadata.merge(source: "bulk_remove", parent_recording_id: parent_recording.id)
              )

              if result.failure?
                failures = [{ attachment_id: attachment_recording.id, error: result.error }]
                raise BatchFailure, result.error
              end

              removed << result.value
            end
          end
        rescue BatchFailure
          return failure("One or more attachments failed to remove", errors: failures)
        end

        success(removed)
      end

      def selected_attachment_recordings
        normalized_ids = normalize_attachment_ids
        raise ArgumentError, "Select at least one attachment to remove" if normalized_ids.empty?

        relation = parent_recording.recordings_query(
          include_children: true,
          type: "RecordingStudioAttachable::Attachment"
        ).where(id: normalized_ids)
        records = relation.to_a
        records_by_id = records.index_by { |record| record.id.to_s }

        unless normalized_ids.all? { |id| records_by_id.key?(id) }
          raise ArgumentError, "One or more attachments do not belong to this recording"
        end

        normalized_ids.map { |id| attachment_recording!(records_by_id.fetch(id)) }
      end

      def normalize_attachment_ids
        ids = Array(attachment_recordings).filter_map do |recording|
          recording.respond_to?(:id) ? recording.id : recording
        end

        ids.concat(Array(attachment_ids))
        ids = ids.filter_map { |id| id.to_s.strip.presence }
        ids.uniq
      end
    end
  end
end
