# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class TrashLibrary < ApplicationService
      def initialize(library_recording:, actor: nil, impersonator: nil)
        @library_recording = library_recording
        @actor = actor
        @impersonator = impersonator
      end

      private

      attr_reader :library_recording, :actor, :impersonator

      def perform
        require_recording_studio!
        library = require_library!

        if library.respond_to?(:recording_studio_trashable_trash!)
          library.recording_studio_trashable_trash!(actor: resolve_actor(actor), impersonator: impersonator)
        else
          library.destroy!
        end

        success(library)
      end

      def require_library!
        raise ArgumentError, "A library is required" unless Placements.library_recording?(library_recording)

        library_recording
      end
    end
  end
end
