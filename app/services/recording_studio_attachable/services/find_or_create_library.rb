# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class FindOrCreateLibrary < ApplicationService
      def initialize(parent_recording: nil, root_recording: nil, actor: nil)
        @parent_recording = parent_recording || root_recording
        @actor = actor
      end

      private

      attr_reader :parent_recording, :actor

      def perform
        require_recording_studio!
        parent = require_parent!
        existing = LibraryQuery.default_for_parent(parent)
        return success(existing) if existing.present?

        restored = restore_trashed_library(parent)
        return success(restored) if restored.present?

        success(create_library(parent))
      end

      def require_parent!
        raise ArgumentError, "A parent is required" if parent_recording.blank?
        return parent_recording if parent_recording.respond_to?(:id) && parent_recording.id.present?

        raise ArgumentError, "A parent is required"
      end

      def restore_trashed_library(parent)
        trashed = LibraryQuery.trashed_default_for_parent(parent)
        return if trashed.blank?
        return unless trashed.respond_to?(:recording_studio_trashable_restore!)

        trashed.recording_studio_trashable_restore!(actor: resolve_actor(actor))
        trashed
      end

      def create_library(parent)
        event = RecordingStudio.record!(
          action: "created",
          recordable: RecordingStudioAttachable::Library.new(name: LibraryQuery::DEFAULT_NAME, default: true),
          root_recording: LibraryQuery.root_for(parent),
          parent_recording: parent,
          actor: resolve_actor(actor),
          idempotency_key: LibraryQuery.default_idempotency_key(parent)
        )
        event.recording
      end
    end
  end
end
