# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class RenameLibrary < ApplicationService
      def initialize(library_recording:, name:, description: :keep, actor: nil)
        @library_recording = library_recording
        @name = name
        @description = description
        @actor = actor
      end

      private

      attr_reader :library_recording, :name, :description, :actor

      def perform
        require_recording_studio!
        library = require_library!
        title = name.to_s.strip
        raise ArgumentError, I18n.t("recording_studio_attachable.libraries.name_blank") if title.blank?

        apply_name(library, title)
        success(library)
      end

      def require_library!
        raise ArgumentError, "A library is required" unless Placements.library_recording?(library_recording)

        library_recording
      end

      def apply_name(library, title)
        root = LibraryQuery.root_for(library)
        if root.respond_to?(:revise)
          root.revise(library, actor: resolve_actor(actor)) { |recordable| assign_attributes(recordable, title) }
        else
          assign_attributes(library.try(:recordable), title)
        end
      end

      def assign_attributes(recordable, title)
        return if recordable.blank?

        recordable.name = title if recordable.respond_to?(:name=)
        return if description == :keep || !recordable.respond_to?(:description=)

        recordable.description = description.to_s.strip.presence
      end
    end
  end
end
