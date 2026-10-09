# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    module PlacementGuards
      private

      def assert_placement_enabled!(recording)
        RecordingStudioAttachable::Authorization.assert_placement_enabled!(recording: recording)
      end

      def authorize_placement!(action:, actor:, recording:)
        RecordingStudioAttachable::Authorization.authorize_placement!(
          action: action,
          actor: actor,
          recording: recording
        )
      end

      def assert_same_root!(parent, attachment)
        return if same_root?(parent, attachment)

        raise ArgumentError, I18n.t(
          "recording_studio_attachable.placements.different_workspace",
          default: "That photo belongs to another workspace."
        )
      end

      def same_root?(left, right)
        left_root = root_id_for(left)
        right_root = root_id_for(right)
        left_root.present? && left_root == right_root
      end

      def assert_library_image!(parent, attachment)
        return if library_child?(parent, attachment)

        raise ArgumentError, I18n.t(
          "recording_studio_attachable.placements.not_in_library",
          default: "That photo is not in this workspace library."
        )
      end

      def library_child?(parent, attachment)
        return false unless Placements.attachment_recording?(attachment)

        library = existing_library_for(parent)
        return false if library.blank?

        attachment.parent_recording_id.to_s == library.id.to_s
      end

      def existing_library_for(parent)
        root = root_recording_for(parent)
        return if root.blank?

        RecordingStudio::Recording.where(
          parent_recording_id: root.id,
          recordable_type: Placements::LIBRARY_TYPE
        ).find { |recording| recording.try(:trashed_at).blank? }
      rescue StandardError
        nil
      end

      def root_id_for(recording)
        return if recording.blank?

        if recording.respond_to?(:root_recording_id) && recording.root_recording_id.present?
          recording.root_recording_id.to_s
        elsif recording.respond_to?(:id)
          recording.id.to_s
        end
      end
    end
  end
end
