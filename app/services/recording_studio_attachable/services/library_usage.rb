# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class LibraryUsage < ApplicationService
      def initialize(library_recording:)
        @library_recording = library_recording
      end

      private

      attr_reader :library_recording

      def perform
        require_recording_studio!
        return success([]) unless Placements.library_recording?(library_recording)

        success(unique_usages)
      end

      def unique_usages
        usages.uniq { |usage| usage.parent_recording.try(:id) || usage.placement_recording.try(:id) }
      end

      def usages
        attachment_recordings.flat_map do |attachment|
          PlacementUsage.call(attachment_recording: attachment).value || []
        end
      end

      def attachment_recordings
        relation = RecordingStudio::Recording.where(
          parent_recording_id: library_recording.id,
          recordable_type: Placements::ATTACHMENT_TYPE
        )
        relation = relation.includes(:recordable) if relation.respond_to?(:includes)
        relation.to_a
      rescue StandardError
        []
      end
    end
  end
end
