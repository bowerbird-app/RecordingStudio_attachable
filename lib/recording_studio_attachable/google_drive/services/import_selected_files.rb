# frozen_string_literal: true

require "stringio"

module RecordingStudioAttachable
  module GoogleDrive
    module Services
      class ImportSelectedFiles < RecordingStudioAttachable::Adapter::ImportSelectedFiles
        def initialize(parent_recording:, file_ids:, access_token: nil, **options)
          super
        end

        private

        def provider_key
          "google_drive"
        end

        def blank_selection_message
          Copy.t("google_drive.select_at_least_one", default: "Select at least one Google Drive file to import")
        end

        def default_description
          "Imported from Google Drive"
        end

        def extra_selection_keys
          { "resource_key" => %i[resource_key resourceKey] }
        end

        def download_attachment(selection, downloaded)
          file_id = selection.fetch("id")
          resource_key = selection["resource_key"]
          metadata = adapter_client.fetch_file(file_id, resource_key: resource_key)
          reject_oversized_drive_file!(metadata)
          downloaded_file = adapter_client.download(file_id, resource_key: resource_key)
          io = StringIO.new(downloaded_file.body)
          downloaded << io
          {
            io: io,
            filename: downloaded_file.filename,
            content_type: downloaded_file.content_type,
            name: selection["name"].presence || metadata.name,
            description: selection["description"].presence || default_description,
            metadata: {
              provider: provider_key,
              external_id: metadata.id,
              external_url: metadata.web_view_link
            }.compact.merge(selection.fetch("metadata", {}))
          }
        end

        def reject_oversized_drive_file!(metadata)
          max_bytes = RecordingStudioAttachable.configuration.max_file_size
          return if max_bytes.blank?
          return unless metadata.respond_to?(:size)

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
