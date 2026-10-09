# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class RemovePlacement < ApplicationService
      def initialize(parent_recording:, placement_recording:, actor: nil, impersonator: nil)
        @parent_recording = parent_recording
        @placement_recording = placement_recording
        @actor = actor
        @impersonator = impersonator
      end

      private

      attr_reader :parent_recording, :placement_recording, :actor, :impersonator

      def perform
        require_recording_studio!
        parent = require_parent!
        placement = require_placement!(parent)
        assert_placement_enabled!(parent)
        authorize_placement!(action: :remove, actor: resolve_actor(actor), recording: parent)

        if placement.respond_to?(:recording_studio_trashable_trash!)
          placement.recording_studio_trashable_trash!(
            actor: resolve_actor(actor),
            impersonator: impersonator
          )
        else
          placement.destroy!
        end

        success(placement)
      end

      def require_parent!
        raise ArgumentError, "A parent is required" if parent_recording.blank?

        parent_recording
      end

      def require_placement!(parent)
        raise ArgumentError, "That image is not on this page" if placement_recording.blank?
        raise ArgumentError, "That image is not on this page" unless Placements.placement_recording?(placement_recording)
        raise ArgumentError, "That image is not on this page" if placement_recording.parent_recording_id.to_s != parent.id.to_s

        placement_recording
      end
    end
  end
end
