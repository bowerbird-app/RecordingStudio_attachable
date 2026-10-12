# frozen_string_literal: true

module RecordingStudioAttachable
  module LibraryPathOverrides
    def library_item_path_for(item_recording, **options)
      if item_recording.respond_to?(:recordable_type) &&
         item_recording.recordable_type == "RecordingStudioAttachable::Attachment"
        return attachable_engine_routes.attachment_path(item_recording, **options)
      end

      return super if defined?(super)

      nil
    end

    def library_new_item_path_for(library_recording, type: nil, **options)
      type_name = type.presence&.to_s || "RecordingStudioAttachable::Attachment"
      if type_name == "RecordingStudioAttachable::Attachment"
        return attachable_engine_routes.recording_attachment_upload_path(library_recording, **options)
      end

      return super if defined?(super)

      nil
    end

    private

    def attachable_engine_routes
      if respond_to?(:recording_studio_attachable, true)
        recording_studio_attachable
      else
        RecordingStudioAttachable::Engine.routes.url_helpers
      end
    end
  end
end
