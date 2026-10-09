# frozen_string_literal: true

module RecordingStudioAttachable
  module Services
    class UploadToLibraryAndPlace < ApplicationService
      def initialize(parent_recording:, actor: nil, impersonator: nil, **upload)
        @parent_recording = parent_recording
        @actor = actor
        @impersonator = impersonator
        @upload = upload
      end

      private

      attr_reader :parent_recording, :actor, :impersonator, :upload

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
        root = root_recording_for(parent)
        result = FindOrCreateLibrary.call(root_recording: root, actor: resolve_actor(actor))
        raise ArgumentError, result.error if result.failure?

        result.value
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
