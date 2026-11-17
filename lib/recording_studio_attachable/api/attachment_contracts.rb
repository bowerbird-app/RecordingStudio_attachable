# frozen_string_literal: true

require_relative "attachment_copy"

module RecordingStudioAttachable
  module Api
    module AttachmentContracts
      ATTACHMENT_ONE_SCHEMA = AttachmentCopy::Schemas::ONE
      ATTACHMENT_MANY_SCHEMA = AttachmentCopy::Schemas::MANY
      CREATE_UPLOAD_TICKET_SCHEMA = AttachmentCopy::Schemas::TICKET
      CREATE_UPLOAD_FIELDS = AttachmentCopy::Fields::CREATE_UPLOAD

      module_function

      def create_upload
        { reject_unknown: false, fields: CREATE_UPLOAD_FIELDS }
      end

      def attach
        { reject_unknown: false, fields: AttachmentCopy::Fields::ATTACH }
      end

      def import_attachment
        { reject_unknown: false, fields: AttachmentCopy::Fields::IMPORT }
      end
    end
  end
end
