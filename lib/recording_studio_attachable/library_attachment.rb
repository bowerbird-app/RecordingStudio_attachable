# frozen_string_literal: true

module RecordingStudioAttachable
  module LibraryAttachment
    ATTACHMENT_TYPE = "RecordingStudioAttachable::Attachment"

    module_function

    def library_recording?(recording)
      defined?(RecordingStudioLibrary::Placements) &&
        RecordingStudioLibrary::Placements.library_recording?(recording)
    end

    def attrs_for(blob:, **presentation)
      blob_attrs(blob).merge(presentation_attrs(blob, presentation)).compact
    end

    def blob_attrs(blob)
      content_type = blob.content_type.to_s
      {
        attachment_kind: RecordingStudioAttachable.configuration.attachment_kind_for(content_type),
        original_filename: blob.filename.to_s,
        content_type: content_type,
        byte_size: blob.byte_size,
        file: blob
      }
    end

    def presentation_attrs(blob, presentation)
      root = presentation[:root_recording]
      {
        name: presentation[:name].presence || default_name_for(blob),
        description: presentation[:description],
        caption: presentation[:caption],
        credit: presentation[:credit],
        alt_text: presentation[:alt_text],
        validation_options: presentation[:validation_options] || {},
        root_recording_id: root.respond_to?(:id) ? root.id : nil
      }
    end

    def default_name_for(blob)
      blob.filename.base.to_s.presence || blob.filename.to_s
    end
  end
end
