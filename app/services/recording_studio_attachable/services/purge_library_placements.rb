# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class PurgeLibraryPlacements < ApplicationService
      def initialize(library_recording:)
        @library_recording = library_recording
      end

      private

      attr_reader :library_recording

      def perform
        require_recording_studio!
        return success([]) unless Placements.library_recording?(library_recording)

        removed = attachment_recordings.flat_map do |attachment|
          PurgePlacements.call(attachment_recording: attachment).value || []
        end
        success(removed)
      end

      def attachment_recordings
        scope = RecordingStudio::Recording
        scope = scope.unscoped if scope.respond_to?(:unscoped)
        relation = scope.where(
          parent_recording_id: library_recording.id,
          recordable_type: Placements::ATTACHMENT_TYPE
        )
        relation.to_a
      rescue StandardError
        []
      end
    end
  end
end
