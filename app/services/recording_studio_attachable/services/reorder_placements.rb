# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class ReorderPlacements < ApplicationService
      def initialize(parent_recording:, ordered_recording_ids:, actor: nil)
        @parent_recording = parent_recording
        @ordered_recording_ids = ordered_recording_ids
        @actor = actor
      end

      private

      attr_reader :parent_recording, :ordered_recording_ids, :actor

      def perform
        require_recording_studio!
        parent = require_parent!
        assert_placement_enabled!(parent)
        authorize_placement!(action: :revise, actor: resolve_actor(actor), recording: parent)
        raise ArgumentError, "This page cannot reorder photos" unless parent.respond_to?(:recording_studio_orderable_reorder!)

        parent.recording_studio_orderable_reorder!(
          ordered_recording_ids: Array(ordered_recording_ids),
          actor: resolve_actor(actor)
        )
        success(parent)
      end

      def require_parent!
        raise ArgumentError, "A parent is required" if parent_recording.blank?

        parent_recording
      end
    end
  end
end
