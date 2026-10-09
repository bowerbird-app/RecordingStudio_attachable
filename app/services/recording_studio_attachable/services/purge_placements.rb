# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class PurgePlacements < ApplicationService
      def initialize(attachment_recording:)
        @attachment_recording = attachment_recording
      end

      private

      attr_reader :attachment_recording

      def perform
        require_recording_studio!
        return success([]) unless Placements.attachment_recording?(attachment_recording)

        removed = destroy_placements
        success(removed)
      end

      def destroy_placements
        placement_recordings.each(&:destroy!)
      end

      def placement_recordings
        ids = placement_recordable_ids
        return [] if ids.empty?

        scope = RecordingStudio::Recording
        scope = scope.unscoped if scope.respond_to?(:unscoped)
        scope.where(recordable_type: Placements::PLACEMENT_TYPE, recordable_id: ids).to_a
      end

      def placement_recordable_ids
        return [] unless defined?(RecordingStudioAttachable::Placement)

        RecordingStudioAttachable::Placement.where(attachment_recording_id: attachment_recording.id).pluck(:id)
      rescue StandardError
        []
      end
    end
  end
end
