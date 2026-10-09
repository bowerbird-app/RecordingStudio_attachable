# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class UploadToLibraryAndPlace < ApplicationService
      def initialize(parent_recording:, actor: nil, impersonator: nil, library_recording: nil, **upload)
        @parent_recording = parent_recording
        @actor = actor
        @impersonator = impersonator
        @library_recording = library_recording
        @upload = upload
      end

      private

      attr_reader :parent_recording, :actor, :impersonator, :library_recording, :upload

      def perform
        require_recording_studio!
        parent = require_parent!
        assert_placement_enabled!(parent)
        authorize_placement!(action: :upload, actor: resolve_actor(actor), recording: parent)

        library = library_for!(parent)
        attachment = upload_to_library!(library)
        PlaceLibraryImage.call(
          parent_recording: parent,
          attachment_recording: attachment,
          actor: resolve_actor(actor),
          impersonator: impersonator
        ).then do |result|
          raise ArgumentError, result.error if result.failure?

          success(result.value)
        end
      end

      def require_parent!
        raise ArgumentError, "A parent is required" if parent_recording.blank?

        parent_recording
      end

      def library_for!(parent)
        library = library_recording.presence || default_library_for(parent)
        raise ArgumentError, I18n.t("recording_studio_attachable.placements.not_in_library") unless LibraryQuery.live?(library)
        raise ArgumentError, I18n.t("recording_studio_attachable.placements.different_workspace") unless same_root?(parent, library)

        library
      end

      def default_library_for(parent)
        result = FindOrCreateLibrary.call(
          parent_recording: image_library_parent_for(parent),
          actor: resolve_actor(actor)
        )
        raise ArgumentError, result.error if result.failure?

        result.value
      end

      def image_library_parent_for(parent)
        current = parent
        while current
          return current if image_library_enabled?(current)

          next_parent = current.try(:parent_recording)
          break if next_parent.blank? || next_parent == current

          current = next_parent
        end

        root_recording_for(parent)
      end

      def image_library_enabled?(recording)
        type = recording.try(:recordable_type)
        return false if type.blank? || !defined?(RecordingStudio)

        if RecordingStudio.respond_to?(:configuration) && RecordingStudio.configuration.respond_to?(:capability_enabled?)
          RecordingStudio.configuration.capability_enabled?(:image_library, for_type: type)
        else
          RecordingStudio.respond_to?(:capability_enabled?) &&
            RecordingStudio.capability_enabled?(:image_library, for: type)
        end
      rescue StandardError
        false
      end

      def upload_to_library!(library)
        raise ArgumentError, "Upload a photo to add it" unless upload[:signed_blob_id].present? || upload[:io].present?

        upload_one(library)
      end

      def upload_one(library)
        service = if upload[:io].present?
                    ImportAttachment
                  else
                    RecordAttachmentUpload
                  end

        result = service.call(parent_recording: library, actor: resolve_actor(actor), impersonator: impersonator, **upload)
        raise ArgumentError, result.error if result.failure?

        result.value
      end
    end
  end
end
