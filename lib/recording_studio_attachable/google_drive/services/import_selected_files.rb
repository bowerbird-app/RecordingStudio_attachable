# frozen_string_literal: true

require_relative "../../../../app/services/recording_studio_attachable/services/application_service"

module RecordingStudioAttachable
  module GoogleDrive
    module Services
      class ImportSelectedFiles < RecordingStudioAttachable::Services::ApplicationService
        def initialize(parent_recording:, file_ids:, access_token:, actor: nil, impersonator: nil, client: nil)
          super()
          @parent_recording = parent_recording
          @file_ids = file_ids
          @access_token = access_token
          @actor = actor
          @impersonator = impersonator
          @client = client
        end

        private

        attr_reader :parent_recording, :file_ids, :access_token, :actor, :impersonator, :client

        def perform
          selections = normalized_file_selections
          raise ArgumentError, "Select at least one Google Drive file to import" if selections.blank?

          attachments = selections.map do |selection|
            fetch_options = {}
            fetch_options[:resource_key] = selection["resource_key"] if selection["resource_key"].present?

            file = google_drive_client.fetch_file(selection.fetch("id"), **fetch_options)
            downloaded = google_drive_client.download_file(file)

            downloaded.merge(
              name: file.fetch("name"),
              description: "Imported from Google Drive",
              metadata: {
                provider: "google_drive",
                external_id: file.fetch("id"),
                external_url: file["webViewLink"]
              }.compact
            )
          end

          RecordingStudioAttachable::Services::ImportAttachments.call(
            parent_recording: parent_recording,
            attachments: attachments,
            actor: actor,
            impersonator: impersonator,
            source: "google_drive"
          )
        end

        def normalized_file_selections
          Array(file_ids).filter_map do |selection|
            case selection
            when String
              selection.presence && { "id" => selection }
            when Hash
              normalized_selection_hash(selection)
            end
          end.uniq
        end

        def normalized_selection_hash(selection)
          id = selection["id"] || selection[:id]
          return if id.blank?

          resource_key = selection["resource_key"] || selection[:resource_key] || selection["resourceKey"] || selection[:resourceKey]

          { "id" => id.to_s, "resource_key" => resource_key.to_s.presence }.compact
        end

        def google_drive_client
          @google_drive_client ||= client || RecordingStudioAttachable::GoogleDrive::Client.new(access_token: access_token)
        end
      end
    end
  end
end
