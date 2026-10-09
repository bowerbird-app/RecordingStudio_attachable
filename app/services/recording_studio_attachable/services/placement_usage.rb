# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class PlacementUsage < ApplicationService
      def initialize(attachment_recording:)
        @attachment_recording = attachment_recording
      end

      private

      attr_reader :attachment_recording

      def perform
        require_recording_studio!
        return success([]) unless Placements.attachment_recording?(attachment_recording)

        success(usages)
      end

      def usages
        placement_recordings.filter_map do |placement|
          next if placement.try(:trashed_at).present?

          parent = placement.try(:parent_recording)
          next if parent.blank?

          Placements::Usage.new(
            placement_recording: placement,
            parent_recording: parent,
            label: Placements.place_label(parent)
          )
        end
      end

      def placement_recordings
        ids = placement_recordable_ids
        return [] if ids.empty?

        relation = RecordingStudio::Recording.where(
          recordable_type: Placements::PLACEMENT_TYPE,
          recordable_id: ids
        )
        relation = relation.includes(:recordable, :parent_recording) if relation.respond_to?(:includes)
        relation.order(:created_at, :id).to_a
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
