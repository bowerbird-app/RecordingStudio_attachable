# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class PlaceLibraryImage < ApplicationService
      def initialize(parent_recording:, attachment_recording:, actor: nil, impersonator: nil)
        @parent_recording = parent_recording
        @attachment_recording = attachment_recording
        @actor = actor
        @impersonator = impersonator
      end

      private

      attr_reader :parent_recording, :attachment_recording, :actor, :impersonator

      def perform
        require_recording_studio!
        parent = require_parent!
        attachment = require_attachment!
        assert_placement_enabled!(parent)
        assert_same_root!(parent, attachment)
        assert_library_image!(parent, attachment)
        authorize_placement!(action: :upload, actor: resolve_actor(actor), recording: parent)

        placement = record_placement(parent, attachment)
        append_order(parent, placement)
        success(placement)
      end

      def require_parent!
        raise ArgumentError, "A parent is required" if parent_recording.blank?

        parent_recording
      end

      def require_attachment!
        attachment_recording!(attachment_recording)
      end

      def record_placement(parent, attachment)
        parent.record(RecordingStudioAttachable::Placement, parent_recording: parent, actor: resolve_actor(actor)) do |placement|
          placement.attachment_recording_id = attachment.id
        end
      end

      def append_order(parent, placement)
        return unless parent.respond_to?(:recording_studio_orderable_append!)

        parent.recording_studio_orderable_append!(placement, actor: resolve_actor(actor))
      rescue StandardError
        placement
      end
    end
  end
end
