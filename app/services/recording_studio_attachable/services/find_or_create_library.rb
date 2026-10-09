# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class FindOrCreateLibrary < ApplicationService
      def initialize(root_recording:, actor: nil)
        @root_recording = root_recording
        @actor = actor
      end

      private

      attr_reader :root_recording, :actor

      def perform
        require_recording_studio!
        root = require_root!
        existing = existing_library(root)
        return success(existing) if existing.present?

        restored = restore_trashed_library(root)
        return success(restored) if restored.present?

        success(create_library(root))
      end

      def require_root!
        raise ArgumentError, "A workspace is required" if root_recording.blank?
        return root_recording if root_recording.respond_to?(:id) && root_recording.id.present?

        raise ArgumentError, "A workspace is required"
      end

      def existing_library(root)
        library_scope(root).find { |recording| recording.try(:trashed_at).blank? }
      end

      def restore_trashed_library(root)
        trashed = library_scope(root).find { |recording| recording.try(:trashed_at).present? }
        return if trashed.blank?
        return unless trashed.respond_to?(:recording_studio_trashable_restore!)

        trashed.recording_studio_trashable_restore!(actor: resolve_actor(actor))
        trashed
      end

      def create_library(root)
        event = RecordingStudio.record!(
          action: "created",
          recordable: RecordingStudioAttachable::Library.new,
          root_recording: root,
          parent_recording: root,
          actor: resolve_actor(actor),
          idempotency_key: "recording-studio-attachable-library:#{root.id}"
        )
        event.recording
      end

      def library_scope(root)
        relation = RecordingStudio::Recording.where(
          parent_recording_id: root.id,
          recordable_type: RecordingStudioAttachable::Placements::LIBRARY_TYPE
        )
        return Array(relation) unless relation.respond_to?(:includes)

        relation = relation.where(root_recording_id: root.id) if relation.respond_to?(:where)
        relation = relation.includes(:recordable) if relation.respond_to?(:includes)
        relation = relation.order(:created_at, :id) if relation.respond_to?(:order)
        relation.to_a
      rescue StandardError
        []
      end
    end
  end
end
