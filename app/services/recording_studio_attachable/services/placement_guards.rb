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
          default: "That photo is not in a library in this workspace."
        )
      end

      def library_child?(parent, attachment)
        return false unless Placements.attachment_recording?(attachment)

        library = library_for_attachment(attachment)
        return false unless LibraryQuery.live?(library)

        same_root?(parent, library)
      end

      def library_for_attachment(attachment)
        parent = attachment.try(:parent_recording)
        return parent if parent.present?

        id = attachment.try(:parent_recording_id)
        return if id.blank?

        RecordingStudio::Recording.find_by(id: id)
      rescue StandardError
        nil
      end

      def existing_library_for(parent)
        LibraryQuery.default_for_parent(root_recording_for(parent)) ||
          LibraryQuery.default_for_parent(parent)
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
