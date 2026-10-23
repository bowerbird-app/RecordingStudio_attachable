# frozen_string_literal: true

require "marcel"
require "stringio"

module RecordingStudioAttachable
  module Dropbox
    module Services
      class ImportSelectedFiles < RecordingStudioAttachable::Adapter::ImportSelectedFiles
        def initialize(parent_recording:, file_ids:, access_token: nil, **options)
          super
        end

        private

        def provider_key
          "dropbox"
        end

        def blank_selection_message
          Copy.t("dropbox.select_at_least_one", default: "Select at least one Dropbox file to import")
        end

        def default_description
          "Imported from Dropbox"
        end

        def download_attachment(selection, downloaded)
          path = selection.fetch("id")
          metadata = adapter_client.fetch_file(path: path)
          reject_oversized_file!(metadata)
          downloaded_file = adapter_client.download(path: path)
          io = StringIO.new(downloaded_file.body)
          downloaded << io
          attachment_attributes(selection, metadata, downloaded_file, io)
        end

        def attachment_attributes(selection, metadata, downloaded_file, io)
          filename = downloaded_file.filename.presence || metadata.name
          {
            io: io,
            filename: filename,
            content_type: downloaded_file.content_type.presence || Marcel::MimeType.for(name: filename),
            name: selection["name"].presence || metadata.name,
            description: selection["description"].presence || default_description,
            metadata: attachment_metadata(selection, metadata)
          }
        end

        def attachment_metadata(selection, metadata)
          {
            provider: provider_key,
            external_id: metadata.id,
            external_url: metadata.path
          }.compact.merge(selection.fetch("metadata", {}))
        end

        def reject_oversized_file!(metadata)
          max_bytes = RecordingStudioAttachable.configuration.max_file_size
          return if max_bytes.blank?

          size = metadata.size
          return if size.nil?

          raise ArgumentError, "Remote file exceeds maximum file size" if size > max_bytes
        end

        def build_client
          Integration.client(root: root_recording_for(parent_recording), actor: actor)
        end
      end
    end
  end
end
