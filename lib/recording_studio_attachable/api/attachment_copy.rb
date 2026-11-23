# frozen_string_literal: true

module RecordingStudioAttachable
  module Api
    module AttachmentCopy
      module Schemas
        ONE = {
          type: "object",
          properties: {
            id: { type: "string", description: "The new attachment recording id." },
            kind: {
              type: "string",
              description: "image when the content type starts with image/, and file otherwise."
            },
            name: { type: "string", description: "The attachment name." },
            urls: {
              type: "object",
              description: "Delivery location for the original file.",
              properties: {
                file: {
                  type: "string",
                  description: "Delivery URL for the original file. The default rails mode returns the " \
                               "engine file path. Direct mode returns the blob direct URL."
                }
              }
            }
          }
        }.freeze
        MANY = {
          type: "object",
          properties: {
            attachments: {
              type: "array",
              description: "One object per file attached in this call. Each object has id, kind, name, and urls.file.",
              items: ONE
            }
          }
        }.freeze
        TICKET = {
          type: "object",
          properties: {
            signed_blob_id: {
              type: "string",
              description: "Signed id to send to attach after the PUT. Bound to this record and the actor " \
                           "that called create_upload."
            },
            upload: {
              type: "object",
              description: "Where to PUT the file bytes.",
              properties: {
                url: { type: "string", description: "URL that receives the PUT of the file bytes." },
                headers: { type: "object", description: "Headers to send with that PUT." }
              }
            },
            expires_at: {
              type: "string",
              format: "date-time",
              description: "ISO 8601 time when the signed id stops working."
            }
          }
        }.freeze
      end

      module Fields
        RECORD_LIMIT_NOTE =
          "It must match this record type's allowed content types and size and count limits, " \
          "as shown in the action description."
        ATTACHMENTS_LEAD =
          "List of files to attach in one call. Each item has signed_blob_id from its own " \
          "create_upload call, plus optional name, description, caption, credit, and alt_text. " \
          "Send this or signed_blob_id, not both. "
        TYPE = {
          type: :string, required: false, allow_blank: false,
          description: "Public type of the parent record, such as Workspace. Call describe if you do not know it."
        }.freeze
        CREATE_UPLOAD = {
          type: TYPE,
          filename: {
            type: :string, required: true, allow_blank: false,
            description: "The file name to store, such as cover.jpg. Required. Send the name you want on the blob."
          },
          byte_size: {
            type: :integer, required: true,
            description: "The file size in bytes. Required. Use zero or more. #{RECORD_LIMIT_NOTE}".freeze
          },
          checksum: {
            type: :string, required: true, allow_blank: false,
            description: "MD5 checksum of the file bytes, Base64-encoded, as Active Storage expects. Required. " \
                         "Compute it from the bytes before you call create_upload."
          },
          content_type: {
            type: :string, required: true, allow_blank: false,
            description: "The file's content type. Required. #{RECORD_LIMIT_NOTE} " \
                         "image/* does not include image/svg+xml unless that exact type is named in the allow list.".freeze
          }
        }.freeze
        ATTACH = {
          type: TYPE,
          signed_blob_id: {
            type: :string, required: false, allow_blank: true,
            description: "Signed id from create_upload, after you PUT the file bytes to upload.url. " \
                         "It is bound to this record and the actor that called create_upload. " \
                         "Send this or attachments, not both."
          },
          name: {
            type: :string, required: false, allow_blank: true,
            description: "Optional display name. When omitted, the name is the uploaded file name without its extension."
          },
          description: {
            type: :string, required: false, allow_blank: true,
            description: "Optional longer text stored on the attachment. Omit it to store none."
          },
          caption: {
            type: :string, required: false, allow_blank: true,
            description: "Optional caption stored on the attachment. Omit it to store none."
          },
          credit: {
            type: :string, required: false, allow_blank: true,
            description: "Optional credit line stored on the attachment. Omit it to store none."
          },
          alt_text: {
            type: :string, required: false, allow_blank: true,
            description: "Optional alt text stored on the attachment. Omit it to store none."
          },
          attachments: {
            type: :array, required: false,
            description: "#{ATTACHMENTS_LEAD}#{RECORD_LIMIT_NOTE}".freeze
          }
        }.freeze
        IMPORT = {
          type: TYPE,
          url: {
            type: :string, required: true, allow_blank: false,
            description: "Public HTTPS URL of the file to download. The port must be 443 and the address must be public. " \
                         "The host app must allow that remote host for imports. By default no remote hosts are allowed."
          },
          name: {
            type: :string, required: false, allow_blank: true,
            description: "Optional display name. When omitted, the name is the file name from the URL, " \
                         "without its extension."
          },
          description: {
            type: :string, required: false, allow_blank: true,
            description: "Optional longer text stored on the attachment. Omit it to store none."
          }
        }.freeze
      end

      module Text
        LIMITS =
          "Allowed types default to image/* and application/pdf. " \
          "image/* does not include image/svg+xml unless that type is named in the allow list. " \
          "The default size cap is 25 MB. " \
          "A batch can include up to 20 files. " \
          "A parent record can set a tighter type list, size cap, or batch cap. " \
          "An image over 40,000,000 pixels, or over 12,000 pixels on the longest side, is refused."
        ONE_RESULT =
          "id is the new attachment recording id. " \
          "kind is image when the content type starts with image/, and file otherwise. " \
          "name is the attachment name. " \
          "urls.file is the delivery URL for the original file. " \
          "The default rails mode returns the engine file path. " \
          "Direct mode returns the blob direct URL."
        ITEM_NOTE =
          "This links the file to the record as an attachment. " \
          "It does not show the file as an item in a list on the record. " \
          "When the record has its own action for a file or image list, use that action if the file " \
          "should appear as an item."
        CREATE_UPLOAD_SUMMARY = "Prepare a direct upload for a file you already have. This does not attach the file."
        CREATE_UPLOAD =
          "An attachment is an uploaded file linked to a record, such as a PDF, an image, or a document. " \
          "Use create_upload when you have the file bytes. " \
          "Use import_attachment when the file is already at an HTTPS URL. " \
          "Call create_upload, PUT the bytes to upload.url with upload.headers, then call attach with " \
          "signed_blob_id. This call adds nothing to the record. The parent record must already exist. " \
          "If the host app sets a storage limit, the file must fit in the space left. " \
          "Returns signed_blob_id, upload.url, upload.headers, and expires_at. " \
          "signed_blob_id is the id attach accepts. upload.url is where you PUT the file bytes. " \
          "upload.headers are the headers for that PUT. " \
          "expires_at is the ISO 8601 time when the signed id stops working. " \
          "The signed id uses the attachable_upload purpose. " \
          "It expires after 5 minutes by default. " \
          "It is bound to this record and the caller that called create_upload. " \
          "attach accepts it once, and only while the blob is still unattached. " \
          "The stored bytes are checked and must match content_type. " \
          "#{LIMITS} " \
          "Unattached uploads for this caller on this root record stop at 20 by default.".freeze
        ATTACH_SUMMARY = "Link an uploaded file to this record as an attachment."
        ATTACH =
          "An attachment is an uploaded file linked to a record, such as a PDF, an image, or a document. " \
          "Use attach after create_upload, once the bytes are stored. " \
          "Use import_attachment when the file is already at an HTTPS URL and you do not have the bytes. " \
          "Send one signed_blob_id, or send attachments to link several files in one call. Do not send both. " \
          "#{ITEM_NOTE} The parent record must already exist. " \
          "Call create_upload first and PUT the bytes before you send signed_blob_id. " \
          "If the host app sets a storage limit, the file must fit in the space left. " \
          "One signed_blob_id returns id, kind, name, and urls.file. " \
          "attachments returns a list named attachments, and each entry has those same fields. " \
          "#{ONE_RESULT} #{LIMITS}".freeze
        IMPORT_SUMMARY = "Download a public HTTPS file and attach it in one call."
        IMPORT =
          "An attachment is an uploaded file linked to a record, such as a PDF, an image, or a document. " \
          "Use import_attachment when the file is already at an HTTPS URL. " \
          "Use create_upload and then attach when you have the bytes. " \
          "This downloads the file and links it to the record. There is no create_upload step and no " \
          "signed_blob_id. #{ITEM_NOTE} The parent record must already exist. " \
          "If the host app sets a storage limit, the file must fit in the space left. " \
          "The host app must allow the remote host for imports. By default no remote hosts are allowed. " \
          "Returns id, kind, name, and urls.file. #{ONE_RESULT} " \
          "url must be HTTPS on port 443. Private addresses are refused. #{LIMITS}".freeze
      end
    end
  end
end
