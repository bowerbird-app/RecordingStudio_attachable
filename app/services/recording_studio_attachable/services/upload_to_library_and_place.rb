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
        resolved_actor = resolve_actor(actor)
        library = library_for!(parent)
        authorize_upload!(parent, library, resolved_actor)
        blob = blob_for!(library)
        root_recording = root_recording_for(parent)
        incoming = RecordingStudioAttachable::StorageLimit::IncomingBytes.for(root_recording, [blob])
        placement = RecordingStudioAttachable::StorageLimit.with_storage_capacity!(root_recording, incoming) do
          RecordingStudioLibrary.place_new!(
            parent,
            library: library,
            type: LibraryAttachment::ATTACHMENT_TYPE,
            attrs: LibraryAttachment.attrs_for(
              blob: blob,
              name: upload[:name],
              description: upload[:description],
              caption: upload[:caption],
              credit: upload[:credit],
              alt_text: upload[:alt_text],
              root_recording: root_recording,
              validation_options: capability_validation_options(capability_options_for(library))
            ),
            actor: resolved_actor
          )
        end
        success(placement)
      end

      def require_parent!
        raise ArgumentError, "A parent is required" if parent_recording.blank?

        parent_recording
      end

      def library_for!(parent)
        library = library_recording.presence || hosted_library_for(parent)
        assert_live_library!(library)
        assert_same_root!(parent, library)
        library
      end

      def authorize_upload!(parent, library, resolved_actor)
        RecordingStudioAttachable::Authorization.authorize_placement!(
          action: :upload,
          actor: resolved_actor,
          recording: parent
        )
        RecordingStudioAttachable::Authorization.authorize_library!(
          action: :upload,
          actor: resolved_actor,
          recording: library
        )
      end

      def assert_live_library!(library)
        return if RecordingStudioLibrary::Services::LibraryQuery.live?(library)

        raise ArgumentError, I18n.t("recording_studio_attachable.placements.not_in_library")
      end

      def assert_same_root!(parent, library)
        return if same_root?(parent, library)

        raise ArgumentError, I18n.t("recording_studio_attachable.placements.different_workspace")
      end

      def hosted_library_for(parent)
        RecordingStudioAttachable.library_for(
          RecordingStudioLibrary::Services::LibraryQuery.library_parent_for(parent),
          actor: resolve_actor(actor)
        )
      end

      def blob_for!(library)
        if upload[:signed_blob_id].present?
          signed_blob!(upload[:signed_blob_id], capability_options: capability_options_for(library))
        elsif upload[:io].present?
          blob = create_imported_blob!(
            io: upload[:io],
            filename: upload[:filename] || upload[:name],
            content_type: upload[:content_type],
            identify: upload.fetch(:identify, true)
          )
          validate_blob!(blob, capability_options: capability_options_for(library))
          blob
        else
          raise ArgumentError, "Upload a photo to add it"
        end
      end

      def same_root?(left, right)
        left_root = left.try(:root_recording_id).presence || left.try(:id)
        right_root = right.try(:root_recording_id).presence || right.try(:id)
        left_root.present? && left_root.to_s == right_root.to_s
      end
    end
  end
end
