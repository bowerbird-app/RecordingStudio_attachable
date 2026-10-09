# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class CreateLibrary < ApplicationService
      def initialize(parent_recording:, name:, description: nil, actor: nil)
        @parent_recording = parent_recording
        @name = name
        @description = description
        @actor = actor
      end

      private

      attr_reader :parent_recording, :name, :description, :actor

      def perform
        require_recording_studio!
        parent = require_parent!
        title = name.to_s.strip
        raise ArgumentError, I18n.t("recording_studio_attachable.libraries.name_blank") if title.blank?

        event = RecordingStudio.record!(
          action: "created",
          recordable: RecordingStudioAttachable::Library.new(
            name: title,
            description: description.to_s.strip.presence,
            default: false
          ),
          root_recording: LibraryQuery.root_for(parent),
          parent_recording: parent,
          actor: resolve_actor(actor)
        )
        success(event.recording)
      end

      def require_parent!
        raise ArgumentError, "A parent is required" if parent_recording.blank?

        parent_recording
      end
    end
  end
end
