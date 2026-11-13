# frozen_string_literal: true

module RecordingStudioAttachable
  module Api
    module AttachmentContracts
      ATTACHMENT_ONE_SCHEMA = {
        type: "object",
        properties: {
          id: { type: "string" },
          kind: { type: "string" },
          name: { type: "string" },
          urls: {
            type: "object",
            properties: {
              file: { type: "string" }
            }
          }
        }
      }.freeze
      CREATE_UPLOAD_TICKET_SCHEMA = {
        type: "object",
        properties: {
          signed_blob_id: { type: "string" },
          upload: {
            type: "object",
            properties: {
              url: { type: "string" },
              headers: { type: "object" }
            }
          },
          expires_at: { type: "string", format: "date-time" }
        }
      }.freeze
      CREATE_UPLOAD_FIELDS = {
        filename: {
          type: :string, required: true, allow_blank: false,
          description: "The file's name, like cover.jpg. Required."
        },
        byte_size: {
          type: :integer, required: true,
          description: "The file's size in bytes. Required. Must be zero or more, and at most 10 MB on a press kit."
        },
        checksum: {
          type: :string, required: true, allow_blank: false,
          description: "The file's MD5 checksum, Base64-encoded, as Active Storage expects. Required."
        },
        content_type: {
          type: :string, required: true, allow_blank: false,
          description: "The file's type, like image/png. Required. " \
                       "On a press kit only image types (image/*) and SVG (image/svg+xml) are accepted."
        }
      }.freeze

      module_function

      def create_upload
        { reject_unknown: false, fields: CREATE_UPLOAD_FIELDS }
      end

      def attach
        { reject_unknown: false, fields: attach_fields }
      end

      def import_attachment
        { reject_unknown: false, fields: import_fields }
      end

      def attach_fields
        {
          signed_blob_id: { type: :string, required: false, allow_blank: true },
          name: optional_string,
          description: optional_string,
          caption: optional_string,
          credit: optional_string,
          alt_text: optional_string,
          attachments: { type: :array, required: false }
        }
      end

      def import_fields
        {
          url: { type: :string, required: true, allow_blank: false },
          name: optional_string,
          description: optional_string
        }
      end

      def optional_string
        { type: :string, required: false, allow_blank: true }
      end
    end
  end
end
