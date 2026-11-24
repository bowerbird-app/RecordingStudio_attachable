# frozen_string_literal: true

require_relative "attachment_copy"

module RecordingStudioAttachable
  module Api
    module AttachmentContracts
      ATTACHMENT_ONE_SCHEMA = AttachmentCopy::Schemas::ONE
      ATTACHMENT_MANY_SCHEMA = AttachmentCopy::Schemas::MANY
      CREATE_UPLOAD_TICKET_SCHEMA = AttachmentCopy::Schemas::TICKET

      module_function

      def create_upload
        { reject_unknown: false, fields: AttachmentCopy::Fields.create_upload }
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
