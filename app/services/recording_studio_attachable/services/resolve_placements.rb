# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class ResolvePlacements < ApplicationService
      def initialize(parent_recording:, include_trashed_images: false)
        @parent_recording = parent_recording
        @include_trashed_images = include_trashed_images
      end

      private

      attr_reader :parent_recording, :include_trashed_images

      def perform
        require_recording_studio!
        return success([]) if parent_recording.blank?

        success(resolved_items)
      end

      def resolved_items
        placement_children.filter_map do |child|
          next if hidden_placement?(child)

          attachment_recording = attachment_for(child)
          next unless usable_image?(attachment_recording)

          Placements::Resolved.new(
            placement_recording: child,
            attachment_recording: attachment_recording,
            attachment: attachment_recording.recordable
          )
        end
      end

      def placement_children
        if parent_recording.respond_to?(:recording_studio_orderable_children)
          Array(parent_recording.recording_studio_orderable_children)
        else
          children_relation.to_a
        end
      end

      def children_relation
        relation = parent_recording.child_recordings.where(recordable_type: Placements::PLACEMENT_TYPE)
        relation = relation.includes(:recordable) if relation.respond_to?(:includes)
        if relation.respond_to?(:order)
          relation.order(:created_at, :id)
        else
          relation
        end
      end

      def hidden_placement?(child)
        child.try(:trashed_at).present? || !Placements.placement_recording?(child)
      end

      def attachment_for(child)
        id = child.recordable.try(:attachment_recording_id)
        return if id.blank?

        RecordingStudio::Recording.includes(:recordable).find_by(id: id)
      end

      def usable_image?(attachment_recording)
        return false unless Placements.attachment_recording?(attachment_recording)
        return false if attachment_recording.recordable.blank?
        return false unless same_root?(parent_recording, attachment_recording)
        return false unless library_child?(parent_recording, attachment_recording)
        return true if include_trashed_images

        attachment_recording.try(:trashed_at).blank?
      end
    end
  end
end
