# frozen_string_literal: true

module RecordingStudioAttachable
  module McpCopy
    module Text
      module_function

      def type_description(type)
        "#{type.to_s.demodulize} records can take file uploads. Call describe for the upload tools."
      end

      def for(action, upload:, attach:, import:, limits:)
        case action
        when :create_upload then upload_text(upload, attach, import, limits)
        when :attach then attach_text(upload, attach, import, limits)
        when :import_attachment then import_text(upload, attach, import, limits)
        else raise ArgumentError, "Unknown Attachable MCP action #{action.inspect}"
        end
      end

      def upload_text(upload, attach, import, limits)
        "An attachment is an uploaded file linked to a record, such as a PDF, an image, or a document. " \
          "Call #{upload} when you have the file bytes. " \
          "Call #{import} when the file is already at an HTTPS URL. " \
          "Call #{upload}, PUT the bytes to upload.url with upload.headers, then call #{attach} with " \
          "signed_blob_id. This call adds nothing to the record. The parent record must already exist. " \
          "Returns signed_blob_id, upload.url, upload.headers, and expires_at. " \
          "The signed id expires after 5 minutes by default and is bound to this record and this caller. " \
          "#{attach} accepts it once, and only while the blob is still unattached. " \
          "#{limits} Unattached uploads for this caller on this root record stop at 20 by default."
      end

      def attach_text(upload, attach, import, limits)
        "An attachment is an uploaded file linked to a record, such as a PDF, an image, or a document. " \
          "Call #{attach} after #{upload}, once the bytes are stored. " \
          "Call #{import} when the file is already at an HTTPS URL and you do not have the bytes. " \
          "Send one signed_blob_id, or send attachments to link several files in one call. Do not send both. " \
          "#{Api::AttachmentCopy::Text::ITEM_NOTE} The parent record must already exist. " \
          "Call #{upload} first and PUT the bytes before you send signed_blob_id. " \
          "One signed_blob_id returns id, kind, name, and urls.file. " \
          "attachments returns a list named attachments, and each entry has those same fields. " \
          "#{limits}"
      end

      def import_text(upload, attach, import, limits)
        "An attachment is an uploaded file linked to a record, such as a PDF, an image, or a document. " \
          "Call #{import} when the file is already at an HTTPS URL. " \
          "Call #{upload} and then #{attach} when you have the bytes. " \
          "This downloads the file and links it to the record. There is no upload step and no signed_blob_id. " \
          "#{Api::AttachmentCopy::Text::ITEM_NOTE} The parent record must already exist. " \
          "The host app must allow the remote host for imports. By default no remote hosts are allowed. " \
          "Returns id, kind, name, and urls.file. url must be HTTPS on port 443. Private addresses are refused. " \
          "#{limits}"
      end
      private_class_method :upload_text, :attach_text, :import_text
    end
  end
end
