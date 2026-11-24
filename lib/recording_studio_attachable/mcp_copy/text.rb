# frozen_string_literal: true

module RecordingStudioAttachable
  module McpCopy
    module UploadSentences
      TICKET_LINES = [
        "This call adds nothing to the record. The parent record must already exist.",
        "Returns signed_blob_id, upload.url, upload.headers, and expires_at.",
        "The signed id expires after 5 minutes by default and is bound to this record and this caller."
      ].freeze

      module_function

      def for(names)
        upload = names[:create_upload]
        sentences = []
        sentences << "Call #{names[:import_attachment]} when the file is already at an HTTPS URL." if names[:import_attachment]
        sentences << put_sentence(upload, names[:attach]) if upload
        sentences << without_put(upload) if upload
        sentences.concat(TICKET_LINES)
      end

      def put_sentence(upload, attach)
        return "Call #{upload}, PUT the bytes to upload.url with upload.headers, then call #{attach} with signed_blob_id." if attach

        "Call #{upload} and PUT the bytes to upload.url with upload.headers."
      end

      def without_put(upload)
        "If you cannot PUT the bytes, call #{upload} with url, or with data and filename. " \
          "url is an HTTPS address. data is base64 or a data URI. Both store the bytes and return the same signed_blob_id."
      end
      private_class_method :put_sentence, :without_put
    end

    module Text
      module_function

      def type_description(type)
        "#{type.to_s.demodulize} records can take file uploads. Call describe for the upload tools."
      end

      def for(action, names:, limits:, next_step: nil)
        body = case action
               when :create_upload then upload_text(names, limits)
               when :attach then attach_text(names, limits)
               when :import_attachment then import_text(names, limits)
               else raise ArgumentError, "Unknown Attachable MCP action #{action.inspect}"
               end
        return body if next_step.blank?

        "#{body} #{next_step}"
      end

      INTRO = "An attachment is an uploaded file linked to a record, such as a PDF, an image, or a document."

      def upload_text(names, limits)
        upload = names[:create_upload]
        attach = names[:attach]
        sentences = [INTRO]
        sentences << "Call #{upload} when you have the file bytes, an HTTPS url, or base64 data." if upload
        sentences.concat(UploadSentences.for(names))
        sentences << "#{attach} accepts it once, and only while the blob is still unattached." if attach
        sentences << "#{limits} Unattached uploads for this caller on this root record stop at 20 by default."
        sentences.join(" ")
      end

      def attach_text(names, limits)
        sentences = [INTRO, *attach_routes(names)]
        sentences << "Send one signed_blob_id, or send attachments to link several files in one call. Do not send both."
        sentences << Api::AttachmentCopy::Text::ITEM_NOTE
        sentences << "The parent record must already exist."
        sentences << create_upload_first(names[:create_upload])
        sentences.concat(attach_results(limits))
        sentences.compact.join(" ")
      end

      def create_upload_first(upload)
        return if upload.blank?

        "Call #{upload} first. PUT the bytes, or pass url or data on that call when you cannot PUT, before you send signed_blob_id."
      end

      def attach_routes(names)
        upload = names[:create_upload]
        attach = names[:attach]
        import = names[:import_attachment]
        sentences = []
        sentences << "Call #{attach} after #{upload}, once the bytes are stored." if attach && upload
        sentences << "Call #{attach} once the bytes are stored." if attach && upload.blank?
        sentences << "Call #{import} when the file is already at an HTTPS URL and you do not have the bytes." if import
        sentences
      end

      def attach_results(limits)
        [
          "One signed_blob_id returns id, kind, name, and urls.file.",
          "attachments returns a list named attachments, and each entry has those same fields.",
          limits
        ]
      end

      def import_text(names, limits)
        sentences = [INTRO]
        sentences.concat(import_routes(names))
        sentences << "This downloads the file and links it to the record. There is no upload step and no signed_blob_id."
        sentences << Api::AttachmentCopy::Text::IMPORT_ITEM_NOTE
        sentences.concat(import_limits(limits))
        sentences.join(" ")
      end

      def import_routes(names)
        upload = names[:create_upload]
        attach = names[:attach]
        import = names[:import_attachment]
        sentences = []
        sentences << "Call #{import} when the file is already at an HTTPS URL." if import
        sentences << import_bytes_sentence(upload, attach) if upload
        sentences
      end

      def import_bytes_sentence(upload, attach)
        return "Call #{upload} and then #{attach} when you have the bytes." if attach

        "Call #{upload} when you have the bytes."
      end

      def import_limits(limits)
        [
          "The parent record must already exist.",
          "Public HTTPS hosts are allowed. The host app can limit which hosts imports may use, or turn imports off.",
          "Returns id, kind, name, and urls.file. url must be HTTPS on port 443. Private addresses are refused.",
          limits
        ]
      end
      private_class_method :upload_text, :attach_text, :import_text, :create_upload_first,
                           :attach_routes, :attach_results, :import_routes, :import_bytes_sentence, :import_limits
    end
  end
end
